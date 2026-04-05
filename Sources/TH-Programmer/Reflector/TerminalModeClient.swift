// TerminalModeClient.swift — D-STAR Terminal Mode serial bridge for TH-D74/D75
//
// Bridges the radio's Bluetooth SPP (or USB) serial connection to a reflector client.
// The radio handles AMBE codec and audio — this bridge shuttles frames between
// the serial port and the D-STAR network.
//
// Protocol: JARL/Icom Terminal/AP mode (38400 baud, length-prefixed binary frames).
// Reference: QnetGateway/QnetITAP.cpp, DStarRepeater/IcomController.cpp

import Foundation
import Darwin

final class TerminalModeClient: @unchecked Sendable {

    nonisolated deinit {}

    // MARK: - State

    enum State: String, Sendable {
        case idle
        case polling
        case pinging
        case connected
        case error
    }

    // MARK: - Callbacks

    var onStateChange: ((State, String) -> Void)?
    var onHeaderReceived: ((String) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Properties

    private(set) var state: State = .idle
    private(set) var statusMessage: String = ""

    private var fd: Int32 = -1
    private var readSource: DispatchSourceRead?
    private let serialQueue = DispatchQueue(label: "com.th-programmer.terminal-mode", qos: .userInteractive)
    private var keepaliveTimer: DispatchSourceTimer?
    private var handshakeWork: DispatchWorkItem?

    /// Accumulates partial frames from the serial port.
    private var rxBuffer = Data()

    /// Attached reflector client for network bridging.
    private var reflectorClient: ReflectorClientProtocol?

    /// TX stream state (radio → network).
    private var currentTXStreamID: UInt16?
    private var txNetworkFrameCounter: UInt8 = 0

    /// RX counter for sending voice to radio (network → radio).
    private var rxTxCounter: UInt8 = 0

    // MARK: - Connect

    /// Open the serial port and begin the terminal mode handshake.
    func connect(portPath: String) {
        guard state == .idle else { return }

        // Open serial port
        let descriptor = Darwin.open(portPath, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            let err = String(cString: strerror(errno))
            setState(.error, "Cannot open \(portPath): \(err)")
            return
        }

        // Configure serial port.
        // For Bluetooth SPP virtual ports, baud rate is transparent —
        // but we still need raw mode (no echo, no line editing).
        var options = termios()
        tcgetattr(descriptor, &options)
        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB | CSTOPB | CSIZE | CRTSCTS)
        options.c_cflag |= tcflag_t(CS8)

        // Set baud rate — 38400 for real serial, transparent for BT SPP
        let isBluetooth = portPath.lowercased().contains("th-d7")
            || portPath.lowercased().contains("bluetooth")
        if !isBluetooth {
            cfsetspeed(&options, speed_t(B38400))
        }
        tcsetattr(descriptor, TCSANOW, &options)

        // Flush any stale data
        tcflush(descriptor, TCIOFLUSH)

        self.fd = descriptor
        rxBuffer = Data()

        // Start reading
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: serialQueue)
        source.setEventHandler { [weak self] in
            self?.handleReadEvent()
        }
        source.setCancelHandler { [weak self] in
            self?.readSource = nil
        }
        readSource = source
        source.resume()

        // Begin handshake — listen first for 1s in case radio sends data on connect
        setState(.polling, "Listening for radio…")
        serialQueue.asyncAfter(deadline: .now() + 1.0) { [weak self] in
            self?.beginHandshake()
        }

        // Also try a quick listen on the serial queue
        serialQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.onError?("Port open, waiting for radio data…")
        }
    }

    /// Disconnect from the radio.
    func disconnect() {
        guard state != .idle else { return }
        handshakeWork?.cancel()
        handshakeWork = nil
        stopKeepalive()
        detachReflector()
        readSource?.cancel()
        readSource = nil
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        rxBuffer = Data()
        setState(.idle, "Disconnected")
    }

    // MARK: - Reflector Bridging

    /// Attach a reflector client — voice frames will be bridged both directions.
    func attachReflector(_ client: ReflectorClientProtocol) {
        self.reflectorClient = client
        rxTxCounter = 0

        // Network → radio: receive voice frames from reflector, send to radio
        client.onVoiceFrame = { [weak self] frame in
            self?.serialQueue.async {
                self?.sendVoiceToRadio(frame)
            }
        }

        client.onHeaderReceived = { [weak self] callsign in
            self?.serialQueue.async {
                self?.sendHeaderToRadio(callsign: callsign)
            }
            self?.onHeaderReceived?(callsign)
        }
    }

    /// Detach reflector — stop bridging.
    func detachReflector() {
        reflectorClient?.onVoiceFrame = nil
        reflectorClient?.onHeaderReceived = nil
        reflectorClient = nil
        currentTXStreamID = nil
        txNetworkFrameCounter = 0
        rxTxCounter = 0
    }

    // MARK: - Handshake

    private func beginHandshake() {
        // Send 18 poll packets with short delays, then ping
        let work = DispatchWorkItem { [weak self] in
            guard let self, self.state == .polling else { return }

            // Send polls
            for i in 0..<18 {
                guard self.state == .polling else { return }
                let poll = TerminalModeProtocol.buildPoll()
                self.sendRaw(poll)
                if i < 17 {
                    usleep(UInt32(TerminalModeProtocol.pollIntervalMs * 1000))
                }
            }

            // Short delay then ping
            usleep(100_000) // 100ms

            guard self.state == .polling else { return }
            self.setState(.pinging, "Sending ping…")
            let ping = TerminalModeProtocol.buildPing()
            self.sendRaw(ping)

            // Retry ping up to 5 times
            for attempt in 1...5 {
                usleep(500_000) // 500ms
                guard self.state == .pinging else { return }
                self.onError?("Ping retry \(attempt + 1)/6…")
                self.sendRaw(ping)
            }

            // If still pinging after all retries, fail
            usleep(2_000_000) // 2s final wait
            if self.state == .pinging {
                self.setState(.error, "No pong from radio — check terminal mode (Menu 650)")
            }
        }

        handshakeWork = work
        serialQueue.async(execute: work)
    }

    // MARK: - Serial Read

    private func handleReadEvent() {
        guard fd >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 1024)
        let bytesRead = Darwin.read(fd, &buffer, buffer.count)

        if bytesRead > 0 {
            let data = Data(buffer[0..<bytesRead])
            // Log raw received bytes for debugging
            let hex = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
            onError?("RX \(bytesRead)b: \(hex)")
            rxBuffer.append(data)
            processRxBuffer()
        }
    }

    private func processRxBuffer() {
        // Strip leading 0xFF idle fill bytes
        while !rxBuffer.isEmpty && rxBuffer[rxBuffer.startIndex] == 0xFF {
            rxBuffer.removeFirst()
        }

        while rxBuffer.count >= 2 {
            let length = Int(rxBuffer[rxBuffer.startIndex])

            // Validate length
            guard length >= 2 && length <= 50 else {
                // Invalid — skip one byte and try again
                rxBuffer.removeFirst()
                continue
            }

            // Wait for complete frame
            guard rxBuffer.count >= length else { break }

            // Extract frame
            let frame = Data(rxBuffer.prefix(length))
            rxBuffer.removeFirst(length)

            handleFrame(frame)
        }
    }

    private func handleFrame(_ frame: Data) {
        guard let parsed = TerminalModeProtocol.parseFrame(frame) else { return }

        switch parsed {
        case .pong:
            if state == .polling || state == .pinging {
                handshakeWork?.cancel()
                handshakeWork = nil
                setState(.connected, "Connected to radio")
                startKeepalive()
            }

        case .header(let data):
            handleRadioHeader(data)

        case .voice(let data):
            handleRadioVoice(data)

        case .headerAck:
            // Radio acknowledged our header — good
            break

        case .dataAck:
            // Radio acknowledged our voice frame — good
            break

        case .unknown(let type):
            onError?("Unknown frame type: 0x\(String(format: "%02X", type))")
        }
    }

    // MARK: - Radio TX (radio → network)

    private func handleRadioHeader(_ data: Data) {
        guard state == .connected else { return }

        // Send ACK to radio
        let ack = TerminalModeProtocol.buildHeaderAck()
        sendRaw(ack)

        // Parse callsigns
        if let header = TerminalModeProtocol.parseHeader(data) {
            onHeaderReceived?(header.my)

            // Start a new network TX stream
            let streamID = DExtraProtocol.randomStreamID()
            currentTXStreamID = streamID
            txNetworkFrameCounter = 0

            // Send header to reflector
            reflectorClient?.sendHeader(streamID: streamID, myCallsign: header.my, yourCallsign: header.your, rpt1Callsign: header.rpt1, rpt2Callsign: header.rpt2)
        }
    }

    private func handleRadioVoice(_ data: Data) {
        guard state == .connected else { return }
        guard let voice = TerminalModeProtocol.parseVoice(data) else { return }

        // Send ACK to radio
        let ack = TerminalModeProtocol.buildDataAck(sequence: voice.seqCounter)
        sendRaw(ack)

        // Forward to reflector
        guard let streamID = currentTXStreamID, let client = reflectorClient else { return }

        let isLast = (voice.seqCounter & 0x40) != 0
        let frameCounter = isLast ? (txNetworkFrameCounter | 0x40) : txNetworkFrameCounter

        let dvFrame = DVFrame(
            streamID: streamID,
            frameCounter: frameCounter,
            ambeData: voice.ambe,
            slowData: voice.slowData
        )
        client.sendVoiceFrame(dvFrame)

        if isLast {
            currentTXStreamID = nil
            txNetworkFrameCounter = 0
        } else {
            txNetworkFrameCounter = (txNetworkFrameCounter + 1) % DExtraProtocol.framesPerSuperframe
        }
    }

    // MARK: - Network RX (network → radio)

    private func sendHeaderToRadio(callsign: String) {
        guard state == .connected else { return }
        rxTxCounter = 0

        let header = TerminalModeProtocol.buildHeader(
            myCallsign: callsign,
            yourCallsign: "CQCQCQ  ",
            rpt1Callsign: "DIRECT  ",
            rpt2Callsign: "        "
        )
        sendRaw(header)
    }

    private func sendVoiceToRadio(_ frame: DVFrame) {
        guard state == .connected else { return }

        let seqCounter = frame.isLastFrame ? (frame.sequenceNumber | 0x40) : frame.sequenceNumber

        let voicePacket = TerminalModeProtocol.buildVoice(
            txCounter: rxTxCounter,
            seqCounter: seqCounter,
            ambe: frame.ambeData,
            slowData: frame.slowData
        )
        sendRaw(voicePacket)

        rxTxCounter = rxTxCounter &+ 1
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        stopKeepalive()
        let timer = DispatchSource.makeTimerSource(queue: serialQueue)
        timer.schedule(
            deadline: .now() + TerminalModeProtocol.keepaliveInterval,
            repeating: TerminalModeProtocol.keepaliveInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .connected else { return }
            let ping = TerminalModeProtocol.buildPing()
            self.sendRaw(ping)
        }
        keepaliveTimer = timer
        timer.resume()
    }

    private func stopKeepalive() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }

    // MARK: - Send

    private func sendRaw(_ data: Data) {
        guard fd >= 0 else { return }
        // Log raw sent bytes for debugging
        let hex = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
        onError?("TX \(data.count)b: \(hex)")
        data.withUnsafeBytes { ptr in
            guard let base = ptr.baseAddress else { return }
            var remaining = data.count
            var offset = 0
            while remaining > 0 {
                let written = Darwin.write(fd, base + offset, remaining)
                if written > 0 {
                    offset += written
                    remaining -= written
                } else if written == -1 && errno == EINTR {
                    continue
                } else {
                    break
                }
            }
        }
    }

    // MARK: - State

    private func setState(_ newState: State, _ message: String) {
        state = newState
        statusMessage = message
        onStateChange?(newState, message)
        if newState == .error {
            onError?(message)
        }
    }
}
