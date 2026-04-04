// MMDVMBridge.swift — Bridges MMDVM serial transport to reflector network client

import Foundation

/// Bridges MMDVM serial frames (from TH-D75 in terminal mode) to/from a reflector client.
/// In this mode, the radio handles AMBE codec and audio — the bridge just shuttles frames.
final class MMDVMBridge: @unchecked Sendable {

    nonisolated deinit {}

    // MARK: - State

    enum BridgeState: Equatable, Sendable {
        case idle
        case probing
        case ready
        case bridging
        case reconnecting(attempt: Int)
        case error(String)
    }

    // MARK: - Callbacks

    var onStateChange: ((BridgeState) -> Void)?
    var onHeaderReceived: ((String) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - Properties

    private(set) var state: BridgeState = .idle {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    private(set) var firmwareVersion: String?

    private let transport: any MMDVMTransport
    private let parser = MMDVMParser()
    private var reflectorClient: ReflectorClientProtocol?
    private let bridgeQueue = DispatchQueue(label: "com.th-programmer.mmdvm-bridge", qos: .userInteractive)

    /// Stream ID for the current RX (network → radio) transmission.
    private var currentRXStreamID: UInt16?

    /// Stream ID for the current TX (radio → network) transmission.
    private var currentTXStreamID: UInt16?
    private var txFrameCounter: UInt8 = 0

    /// Timeout for MMDVM probe response.
    private static let probeTimeout: TimeInterval = 10.0

    /// Number of probe retries before giving up.
    private static let maxProbeRetries = 5

    /// Current probe attempt counter.
    private var probeRetryCount = 0

    /// Port used for the current/last connection (needed for reconnect).
    private var lastPort: RadioSerialPort?

    /// Current reconnect attempt (0 = not reconnecting).
    private var reconnectAttempt = 0

    /// Maximum reconnect attempts before giving up.
    private static let maxReconnectAttempts = 10

    /// Whether the user explicitly stopped (suppresses reconnect).
    private var userStopped = false

    /// Periodic GET_STATUS timer to keep the MMDVM/RFCOMM connection alive.
    private var keepaliveTimer: DispatchSourceTimer?

    /// Keepalive interval — send GET_STATUS every 5 seconds.
    private static let keepaliveInterval: TimeInterval = 5.0

    // MARK: - Init

    init(transport: any MMDVMTransport) {
        self.transport = transport
    }

    // MARK: - Start / Stop

    /// Open the serial port and probe for MMDVM firmware.
    func start(port: RadioSerialPort) throws {
        parser.reset()
        probeRetryCount = 0
        reconnectAttempt = 0
        userStopped = false
        lastPort = port
        state = .probing

        transport.onDataReceived = { [weak self] data in
            self?.bridgeQueue.async {
                self?.handleSerialData(data)
            }
        }

        // Detect transport disconnect and trigger reconnect
        transport.onStateChange = { [weak self] transportState in
            self?.bridgeQueue.async {
                guard let self else { return }
                if case .error = transportState, !self.userStopped {
                    self.attemptReconnect()
                } else if case .disconnected = transportState,
                          self.state != .idle, !self.userStopped {
                    self.attemptReconnect()
                }
            }
        }

        try transport.open(port: port)

        // Assert DTR to signal modem
        try? transport.setDTR(true)

        // Settle delay — MMDVM modems and BT SPP ports need time after open.
        // Then begin probe retry loop.
        bridgeQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.sendProbe()
        }

        // Overall timeout
        bridgeQueue.asyncAfter(deadline: .now() + Self.probeTimeout) { [weak self] in
            guard let self, self.state == .probing else { return }
            self.state = .error("No response from radio — is Menu 650 (Reflector TERM Mode) ON?")
            self.onError?("MMDVM probe timed out after \(Self.maxProbeRetries) attempts.")
        }
    }

    /// Send a single probe and schedule a retry if no response.
    private func sendProbe() {
        guard state == .probing else { return }
        probeRetryCount += 1

        let probe = MMDVMProtocol.buildGetVersion()
        do {
            try transport.send(probe)
        } catch {
            onError?("Probe send failed: \(error.localizedDescription)")
        }

        // If no response after 1.5s, retry
        if probeRetryCount < Self.maxProbeRetries {
            bridgeQueue.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                guard let self, self.state == .probing else { return }
                self.onError?("Probe retry \(self.probeRetryCount + 1)/\(Self.maxProbeRetries)…")
                self.sendProbe()
            }
        }
    }

    /// Attach a reflector client for active bridging.
    func attachReflector(_ client: ReflectorClientProtocol) {
        guard state == .ready || state == .bridging else { return }
        self.reflectorClient = client

        // Set up network → radio path: voice frames
        client.onVoiceFrame = { [weak self] frame in
            self?.bridgeQueue.async {
                self?.handleNetworkVoiceFrame(frame)
            }
        }

        // Set up network → radio path: headers
        // The radio MUST receive a D-STAR header before it will play voice.
        client.onHeaderReceived = { [weak self] callsign in
            self?.bridgeQueue.async {
                self?.sendHeaderToRadio(callsign: callsign)
            }
            self?.onHeaderReceived?(callsign)
        }

        state = .bridging
    }

    /// Detach reflector (stop forwarding but keep serial open).
    func detachReflector() {
        reflectorClient?.onVoiceFrame = nil
        reflectorClient?.onHeaderReceived = nil
        reflectorClient = nil
        currentRXStreamID = nil
        currentTXStreamID = nil
        txFrameCounter = 0

        if state == .bridging {
            state = .ready
        }
    }

    /// Stop everything — close serial and detach reflector.
    func stop() {
        userStopped = true
        stopKeepalive()
        detachReflector()
        transport.close()
        parser.reset()
        firmwareVersion = nil
        reconnectAttempt = 0
        lastPort = nil
        state = .idle
    }

    // MARK: - Keepalive

    /// Start periodic GET_STATUS to keep the MMDVM/RFCOMM connection alive.
    private func startKeepalive() {
        stopKeepalive()
        let timer = DispatchSource.makeTimerSource(queue: bridgeQueue)
        timer.schedule(
            deadline: .now() + Self.keepaliveInterval,
            repeating: Self.keepaliveInterval
        )
        timer.setEventHandler { [weak self] in
            guard let self, self.state == .ready || self.state == .bridging else { return }
            do {
                try self.transport.send(MMDVMProtocol.buildGetStatus())
            } catch {
                self.onError?("Keepalive send failed: \(error.localizedDescription)")
            }
        }
        keepaliveTimer = timer
        timer.resume()
    }

    private func stopKeepalive() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }

    // MARK: - Reconnect

    /// Attempt to reconnect with exponential backoff (1s → 2s → 4s … max 30s).
    private func attemptReconnect() {
        // Don't reconnect if already connected and working
        guard !userStopped, let port = lastPort else { return }
        guard state != .ready && state != .bridging else {
            onError?("Reconnect suppressed — already in \(state)")
            return
        }

        reconnectAttempt += 1
        if reconnectAttempt > Self.maxReconnectAttempts {
            state = .error("Reconnect failed after \(Self.maxReconnectAttempts) attempts")
            onError?("Giving up reconnect after \(Self.maxReconnectAttempts) attempts.")
            return
        }

        let delay = min(Double(1 << (reconnectAttempt - 1)), 30.0)  // 1, 2, 4, 8, 16, 30, 30…
        state = .reconnecting(attempt: reconnectAttempt)
        onError?("Bluetooth disconnected — reconnect attempt \(reconnectAttempt)/\(Self.maxReconnectAttempts) in \(Int(delay))s…")

        bridgeQueue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self, !self.userStopped else { return }

            self.parser.reset()
            self.probeRetryCount = 0
            self.state = .probing

            do {
                try self.transport.open(port: port)
                try? self.transport.setDTR(true)
                self.bridgeQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                    self?.sendProbe()
                }
                // Probe timeout — if no response, trigger another reconnect
                self.bridgeQueue.asyncAfter(deadline: .now() + Self.probeTimeout) { [weak self] in
                    guard let self, self.state == .probing, !self.userStopped else { return }
                    self.onError?("Probe timed out during reconnect attempt \(self.reconnectAttempt)")
                    self.attemptReconnect()
                }
            } catch {
                self.onError?("Reconnect open failed: \(error.localizedDescription)")
                self.attemptReconnect()
            }
        }
    }

    // MARK: - Serial Data Handling (radio → app)

    private func handleSerialData(_ data: Data) {
        let hex = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
        onError?("RFCOMM rx: \(data.count)b [\(hex)]")
        let frames = parser.feed(data)
        for frame in frames {
            handleParsedFrame(frame)
        }
    }

    private func handleParsedFrame(_ frame: MMDVMParser.ParsedFrame) {
        switch frame {
        case .version(let version):
            firmwareVersion = version
            if state == .probing {
                onError?("Firmware: \(version) — configuring D-STAR mode…")
                do {
                    try transport.send(MMDVMProtocol.buildSetConfig())
                    try transport.send(MMDVMProtocol.buildSetMode(mode: 0x01))
                } catch {
                    onError?("Config send failed: \(error.localizedDescription)")
                }
                reconnectAttempt = 0
                state = .ready
                startKeepalive()
            }

        case .ack:
            onError?("MMDVM ACK")

        case .nak(let reason):
            onError?("MMDVM NAK: reason \(String(format: "0x%02X", reason))")

        case .status:
            onError?("MMDVM STATUS")

        case .dstarHeader(let payload):
            onError?("MMDVM rx D-STAR HEADER (\(payload.count)b)")
            handleRadioHeader(payload)

        case .dstarVoice(let payload):
            handleRadioVoice(payload)

        case .dstarEOT:
            onError?("MMDVM rx D-STAR EOT")
            handleRadioEOT()

        case .dstarLost:
            onError?("MMDVM rx D-STAR LOST")

        case .unknown:
            onError?("MMDVM rx UNKNOWN frame")
        }
    }

    /// Radio started a TX — extract callsign and begin network stream.
    private func handleRadioHeader(_ payload: Data) {
        guard let client = reflectorClient, state == .bridging else { return }

        if let header = DVFrame.headerFromMMDVM(payload) {
            onHeaderReceived?(header.myCall)
        }

        let streamID = DExtraProtocol.randomStreamID()
        currentTXStreamID = streamID
        txFrameCounter = 0

        // Send header to reflector
        let myCall = DVFrame.headerFromMMDVM(payload)?.myCall ?? ""
        client.sendHeader(streamID: streamID, myCallsign: myCall)
    }

    /// Radio sent a voice frame — forward to network.
    private func handleRadioVoice(_ payload: Data) {
        guard let client = reflectorClient, state == .bridging else { return }
        guard let streamID = currentTXStreamID else { return }

        if let dvFrame = DVFrame.fromMMDVM(payload, streamID: streamID, frameCounter: txFrameCounter) {
            client.sendVoiceFrame(dvFrame)
        }

        txFrameCounter = (txFrameCounter + 1) % DExtraProtocol.framesPerSuperframe
    }

    /// Radio ended TX — send last frame to network.
    private func handleRadioEOT() {
        guard let client = reflectorClient, state == .bridging else { return }
        guard let streamID = currentTXStreamID else { return }

        let lastFrame = DVFrame(
            streamID: streamID,
            frameCounter: txFrameCounter | 0x40,
            ambeData: DExtraProtocol.silenceAMBE,
            slowData: DExtraProtocol.fillerSlowData
        )
        client.sendVoiceFrame(lastFrame)

        currentTXStreamID = nil
        txFrameCounter = 0
    }

    // MARK: - Network Voice Handling (network → radio)

    /// Send a D-STAR header to the radio so it knows a new transmission is starting.
    /// Without this, the radio ignores voice frames.
    /// Deduplicated: only sends the first header per RX stream.
    private func sendHeaderToRadio(callsign: String) {
        // Guard against duplicate headers — reflectors repeat headers for reliability
        // but the radio only needs one.
        if currentRXStreamID != nil {
            return  // already sent header for this stream
        }
        currentRXStreamID = 1  // mark as "header sent" (actual stream ID doesn't matter here)

        let headerFrame = MMDVMProtocol.buildDStarHeader(
            myCallsign: callsign,
            yourCallsign: "CQCQCQ  ",
            rpt1Callsign: "DIRECT  ",
            rpt2Callsign: "        "
        )
        onError?("Sending header to radio for \(callsign) (\(headerFrame.count)b)")
        do {
            try transport.send(headerFrame)
        } catch {
            onError?("Failed to send header to radio: \(error.localizedDescription)")
        }
    }

    private var networkFrameCount = 0

    /// Timestamp of last voice frame sent to radio — used for 20ms pacing.
    private var lastFrameSendTime: UInt64 = 0

    /// 20ms in nanoseconds for voice frame pacing.
    private static let framePacingNanos: UInt64 = 20_000_000

    private func handleNetworkVoiceFrame(_ frame: DVFrame) {
        // Pace voice frames at 20ms intervals — the radio expects steady timing.
        // Network packets arrive in bursts; without pacing the radio drops frames.
        let now = DispatchTime.now().uptimeNanoseconds
        if lastFrameSendTime > 0 {
            let elapsed = now - lastFrameSendTime
            if elapsed < Self.framePacingNanos {
                let sleepNanos = Self.framePacingNanos - elapsed
                Thread.sleep(forTimeInterval: Double(sleepNanos) / 1_000_000_000.0)
            }
        }
        lastFrameSendTime = DispatchTime.now().uptimeNanoseconds

        // Convert DVFrame to MMDVM serial frame and send to radio
        let mmdvmFrame = frame.toMMDVM()
        networkFrameCount += 1
        // Log every 21st frame (once per superframe) to avoid flooding
        if networkFrameCount % 21 == 1 {
            onError?("Voice frame #\(networkFrameCount) → radio (\(mmdvmFrame.count)b, seq=\(frame.sequenceNumber))")
        }
        do {
            try transport.send(mmdvmFrame)
        } catch {
            onError?("Failed to send to radio: \(error.localizedDescription)")
        }

        // If this is the last frame, send EOT to the radio
        if frame.isLastFrame {
            onError?("EOT → radio (total \(networkFrameCount) frames)")
            networkFrameCount = 0
            currentRXStreamID = nil  // reset so next transmission gets a fresh header
            lastFrameSendTime = 0    // reset pacing for next transmission
            let eotFrame = MMDVMProtocol.buildDStarEOT()
            do {
                try transport.send(eotFrame)
            } catch {
                onError?("Failed to send EOT to radio: \(error.localizedDescription)")
            }
        }
    }
}
