// AudioEngine.swift — AVAudioEngine wrapper for D-STAR audio capture and playback

import Foundation
import AVFoundation
import CoreAudio

/// Manages audio capture (mic → PCM) and playback (PCM → speakers) for the reflector gateway.
/// All audio is 8kHz mono Int16 PCM, matching D-STAR's AMBE codec requirements.
///
/// The capture engine is created once via `prepareCaptureEngine()` and kept alive
/// across PTT presses. This avoids repeated macOS TCC microphone permission prompts —
/// each new AVAudioEngine triggers a fresh TCC check on macOS 26.
final class AudioEngine: @unchecked Sendable {

    nonisolated deinit {}

    // MARK: - Configuration

    static let sampleRate: Double = 8000.0
    static let samplesPerFrame: Int = 160  // 20ms at 8kHz

    // MARK: - Playback

    private var playbackEngine: AVAudioEngine?
    private var playerNode: AVAudioPlayerNode?
    private let playbackBuffer = AudioRingBuffer(capacity: 16000)  // 2 seconds
    private var playbackTimer: DispatchSourceTimer?
    private let playbackQueue = DispatchQueue(label: "com.th-programmer.audio-playback", qos: .userInteractive)

    // MARK: - Capture

    private var captureEngine: AVAudioEngine?
    private var captureConverter: AVAudioConverter?
    private var captureTargetFormat: AVAudioFormat?
    private var isCapturing = false
    private var isCaptureEnginePrepared = false

    /// Called with 160 Int16 PCM samples (20ms) when capturing.
    var onCapturedFrame: (([Int16]) -> Void)?

    /// Current RX audio level (0.0–1.0), updated during playback.
    private(set) var rxLevel: Float = 0.0

    /// Current TX audio level (0.0–1.0), updated during capture.
    private(set) var txLevel: Float = 0.0

    // MARK: - Playback Control

    /// Start the playback engine. Call once when connecting to a reflector.
    func startPlayback(outputDeviceID: AudioDeviceID? = nil) throws {
        stopPlayback()

        let engine = AVAudioEngine()
        let player = AVAudioPlayerNode()

        engine.attach(player)

        // 8kHz mono Float32 format for the player node
        guard let format = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                          sampleRate: Self.sampleRate,
                                          channels: 1,
                                          interleaved: false) else {
            throw AudioEngineError.formatError
        }

        engine.connect(player, to: engine.mainMixerNode, format: format)

        // Set output device if specified
        if let deviceID = outputDeviceID {
            setOutputDevice(engine: engine, deviceID: deviceID)
        }

        try engine.start()
        player.play()

        self.playbackEngine = engine
        self.playerNode = player

        // Start a timer that feeds decoded audio from the ring buffer to the player
        startPlaybackPump(format: format)
    }

    /// Stop the playback engine.
    func stopPlayback() {
        playbackTimer?.cancel()
        playbackTimer = nil
        playerNode?.stop()
        playbackEngine?.stop()
        playerNode = nil
        playbackEngine = nil
        playbackBuffer.flush()
        rxLevel = 0.0
    }

    /// Feed decoded PCM samples into the playback ring buffer.
    func enqueueForPlayback(_ samples: [Int16]) {
        playbackBuffer.write(samples)
    }

    private func startPlaybackPump(format: AVAudioFormat) {
        let timer = DispatchSource.makeTimerSource(queue: playbackQueue)
        // Pump every 20ms (one D-STAR frame)
        timer.schedule(deadline: .now(), repeating: .milliseconds(20))
        timer.setEventHandler { [weak self] in
            self?.pumpPlayback(format: format)
        }
        playbackTimer = timer
        timer.resume()
    }

    private func pumpPlayback(format: AVAudioFormat) {
        guard let player = playerNode,
              playbackBuffer.available >= Self.samplesPerFrame else { return }

        let samples = playbackBuffer.read(maxCount: Self.samplesPerFrame)
        guard !samples.isEmpty else { return }

        // Calculate RX level
        let peak = samples.map { abs(Int32($0)) }.max() ?? 0
        rxLevel = Float(peak) / Float(Int16.max)

        // Convert Int16 to Float32 for AVAudioEngine
        guard let pcmBuffer = AVAudioPCMBuffer(pcmFormat: format,
                                                frameCapacity: AVAudioFrameCount(samples.count)) else { return }
        pcmBuffer.frameLength = AVAudioFrameCount(samples.count)

        if let channelData = pcmBuffer.floatChannelData {
            for i in 0..<samples.count {
                channelData[0][i] = Float(samples[i]) / Float(Int16.max)
            }
        }

        player.scheduleBuffer(pcmBuffer)
    }

    // MARK: - Capture Engine Lifecycle

    /// Prepare the capture engine once (called when connecting to a reflector in software mode).
    /// This triggers the macOS TCC microphone permission prompt exactly once.
    /// The engine stays alive until `teardownCaptureEngine()` is called.
    func prepareCaptureEngine(inputDeviceID: AudioDeviceID? = nil) throws {
        guard !isCaptureEnginePrepared else { return }

        let engine = AVAudioEngine()

        // Set input device if specified
        if let deviceID = inputDeviceID {
            setInputDevice(engine: engine, deviceID: deviceID)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)

        // We need 8kHz mono
        guard let targetFormat = AVAudioFormat(commonFormat: .pcmFormatFloat32,
                                                sampleRate: Self.sampleRate,
                                                channels: 1,
                                                interleaved: false) else {
            throw AudioEngineError.formatError
        }

        // Create converter for reuse across PTT presses
        let converter = AVAudioConverter(from: inputFormat, to: targetFormat)

        // Start the engine now — this triggers the TCC prompt once
        try engine.start()

        self.captureEngine = engine
        self.captureConverter = converter
        self.captureTargetFormat = targetFormat
        self.isCaptureEnginePrepared = true
    }

    /// Tear down the capture engine (called when disconnecting from reflector).
    func teardownCaptureEngine() {
        stopCapture()
        captureEngine?.stop()
        captureEngine = nil
        captureConverter = nil
        captureTargetFormat = nil
        isCaptureEnginePrepared = false
    }

    /// Change the input device on the persistent capture engine.
    /// Call this when the user changes the input device while connected.
    func setCaptureInputDevice(_ deviceID: AudioDeviceID) {
        guard let engine = captureEngine else { return }
        let wasCapturing = isCapturing
        if wasCapturing {
            stopCapture()
        }
        setInputDevice(engine: engine, deviceID: deviceID)
        // Rebuild converter with new input format
        let inputFormat = engine.inputNode.outputFormat(forBus: 0)
        if let targetFormat = captureTargetFormat {
            captureConverter = AVAudioConverter(from: inputFormat, to: targetFormat)
        }
        if wasCapturing {
            try? startCapture()
        }
    }

    // MARK: - Capture Control (PTT)

    /// Start capturing audio from the microphone (PTT down).
    /// The capture engine must already be prepared via `prepareCaptureEngine()`.
    func startCapture(inputDeviceID: AudioDeviceID? = nil) throws {
        guard !isCapturing else { return }

        // If engine isn't prepared yet, prepare it now (first PTT press)
        if !isCaptureEnginePrepared {
            try prepareCaptureEngine(inputDeviceID: inputDeviceID)
        }

        guard let engine = captureEngine else {
            throw AudioEngineError.formatError
        }

        // If a specific device was requested and differs from current, update it
        if let deviceID = inputDeviceID, deviceID != 0 {
            setCaptureInputDevice(deviceID)
        }

        let inputNode = engine.inputNode
        let inputFormat = inputNode.outputFormat(forBus: 0)
        let converter = captureConverter
        let samplesPerFrame = Self.samplesPerFrame

        // Accumulate samples until we have a full 160-sample frame
        var sampleAccumulator = [Int16]()

        inputNode.installTap(onBus: 0, bufferSize: 1024, format: inputFormat) { [weak self] buffer, _ in
            guard let self else { return }

            var convertedSamples = [Int16]()

            if let converter, let targetFormat = self.captureTargetFormat {
                // Convert to 8kHz mono
                let frameCount = AVAudioFrameCount(
                    Double(buffer.frameLength) * Self.sampleRate / inputFormat.sampleRate
                )
                guard frameCount > 0,
                      let convertedBuffer = AVAudioPCMBuffer(pcmFormat: targetFormat,
                                                              frameCapacity: frameCount) else { return }

                var error: NSError?
                let inputBlock: AVAudioConverterInputBlock = { _, outStatus in
                    outStatus.pointee = .haveData
                    return buffer
                }
                converter.convert(to: convertedBuffer, error: &error, withInputFrom: inputBlock)

                if let floatData = convertedBuffer.floatChannelData {
                    for i in 0..<Int(convertedBuffer.frameLength) {
                        let sample = Int16(clamping: Int32(floatData[0][i] * Float(Int16.max)))
                        convertedSamples.append(sample)
                    }
                }
            } else {
                // Already at correct format
                if let floatData = buffer.floatChannelData {
                    for i in 0..<Int(buffer.frameLength) {
                        let sample = Int16(clamping: Int32(floatData[0][i] * Float(Int16.max)))
                        convertedSamples.append(sample)
                    }
                }
            }

            // Accumulate and emit 160-sample frames
            sampleAccumulator.append(contentsOf: convertedSamples)
            while sampleAccumulator.count >= samplesPerFrame {
                let frame = Array(sampleAccumulator.prefix(samplesPerFrame))
                sampleAccumulator.removeFirst(samplesPerFrame)

                // Calculate TX level
                let peak = frame.map { abs(Int32($0)) }.max() ?? 0
                self.txLevel = Float(peak) / Float(Int16.max)

                self.onCapturedFrame?(frame)
            }
        }

        isCapturing = true
    }

    /// Stop capturing audio (PTT up). Engine stays alive for next PTT press.
    func stopCapture() {
        if isCapturing {
            captureEngine?.inputNode.removeTap(onBus: 0)
        }
        isCapturing = false
        txLevel = 0.0
    }

    // MARK: - Device Selection

    private func setOutputDevice(engine: AVAudioEngine, deviceID: AudioDeviceID) {
        let outputUnit = engine.outputNode.audioUnit!
        var id = deviceID
        AudioUnitSetProperty(
            outputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    private func setInputDevice(engine: AVAudioEngine, deviceID: AudioDeviceID) {
        let inputUnit = engine.inputNode.audioUnit!
        var id = deviceID
        AudioUnitSetProperty(
            inputUnit,
            kAudioOutputUnitProperty_CurrentDevice,
            kAudioUnitScope_Global,
            0,
            &id,
            UInt32(MemoryLayout<AudioDeviceID>.size)
        )
    }

    // MARK: - Error

    enum AudioEngineError: Error, LocalizedError {
        case formatError

        var errorDescription: String? {
            switch self {
            case .formatError: return "Failed to create audio format"
            }
        }
    }
}
