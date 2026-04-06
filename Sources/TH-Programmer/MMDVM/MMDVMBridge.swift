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

    /// URCALL command callbacks — set by ReflectorStore to handle link/unlink/info/echo.
    var onLinkRequest: ((ReflectorTarget) -> Void)?
    var onUnlinkRequest: (() -> Void)?
    var onInfoRequest: (() -> Void)?
    var onEchoRequest: (() -> Void)?

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

    /// When true, the current TX is a URCALL command — suppress forwarding to reflector.
    /// Set in handleRadioHeader() when a command is detected, cleared in handleRadioEOT().
    private var isCommandTX: Bool = false

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

    /// Announcement player — loads pre-recorded AMBE words from disk.
    private(set) var announcementPlayer: AnnouncementPlayer?

    /// Announcement sender — sends AMBE frames to the radio via MMDVM.
    private var announcementSender: AnnouncementSender?

    /// Periodic GET_STATUS timer to keep the MMDVM/RFCOMM connection alive.
    private var keepaliveTimer: DispatchSourceTimer?

    /// Keepalive interval — send GET_STATUS every 250ms (MMDVMHost standard).
    /// The modem considers the host dead after 2 seconds without a status poll.
    private static let keepaliveInterval: TimeInterval = 0.25

    // MARK: - Init

    init(transport: any MMDVMTransport) {
        self.transport = transport

        // Try to load announcement AMBE files from known locations
        let execDir = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        var candidates = [
            execDir.appendingPathComponent("../Resources/Announcements").standardized.path,
            execDir.appendingPathComponent("../../Resources/Announcements").standardized.path,
        ]
        if let resourcePath = Bundle.main.resourcePath {
            candidates.append(resourcePath + "/Announcements")
        }

        for dir in candidates {
            if let player = AnnouncementPlayer(directory: dir) {
                self.announcementPlayer = player
                break
            }
        }

        self.announcementSender = AnnouncementSender(transport: transport, queue: bridgeQueue)
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

        // Detect transport disconnect and trigger reconnect.
        // Only reconnect AFTER initial connection succeeds (state reaches .ready).
        // During initial open(), the transport may report errors from retry attempts
        // which should NOT trigger reconnect (open() handles its own retries).
        transport.onStateChange = { [weak self] transportState in
            self?.bridgeQueue.async {
                guard let self else { return }
                guard self.state == .ready || self.state == .bridging else {
                    return  // suppress reconnect during initial connection
                }
                if case .error = transportState, !self.userStopped {
                    self.attemptReconnect()
                } else if case .disconnected = transportState, !self.userStopped {
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
        // Log non-STATUS raw data to catch any unrecognized frames from the radio
        let isStatusOnly = data.count == 10 && data.starts(with: [0xE0, 0x0A, 0x01])
        if !isStatusOnly {
            let hex = data.prefix(30).map { String(format: "%02X", $0) }.joined(separator: " ")
            onError?("📨 RAW RFCOMM rx: \(data.count)b [\(hex)]")
        }
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
            // Suppress from log — normal response to SET_CONFIG/SET_MODE
            break

        case .nak(let reason):
            onError?("MMDVM NAK: reason \(String(format: "0x%02X", reason))")

        case .status:
            // Suppress from log — fires every 250ms, would flood UI
            break

        case .dstarHeader(let payload):
            if let header = DVFrame.headerFromMMDVM(payload) {
                onError?("📡 RX HEADER from \(header.myCall) (\(payload.count)b)")
            } else {
                onError?("📡 RX HEADER (\(payload.count)b)")
            }
            handleRadioHeader(payload)

        case .dstarVoice(let payload):
            handleRadioVoice(payload)

        case .dstarEOT:
            onError?("📡 RX END OF TRANSMISSION")
            handleRadioEOT()

        case .dstarLost:
            onError?("📡 RX SIGNAL LOST")

        case .unknown(let cmd, let payload):
            let hex = payload.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
            onError?("⚠️ UNKNOWN MMDVM command 0x\(String(format: "%02X", cmd)) (\(payload.count)b) [\(hex)]")
        }
    }

    /// Reflector callsign for RPT1/RPT2 fields (e.g. "REF001").
    /// Set by ReflectorStore when attaching the reflector.
    var reflectorCallsign: String = ""
    var reflectorModule: Character = "A"

    /// Radio started a TX — inspect URCALL for commands, then rewrite RPT1/RPT2 and forward.
    /// The radio sends DIRECT in RPT1/RPT2 (terminal mode). The reflector needs
    /// proper routing fields to process the stream:
    ///   RPT1 = our callsign + module (e.g. "AI5OS  C")
    ///   RPT2 = reflector + module (e.g. "REF001 C")
    /// CRC is recalculated after rewriting.
    private func handleRadioHeader(_ payload: Data) {
        guard payload.count >= 41 else { return }

        let header = DVFrame.headerFromMMDVM(payload)
        if let header {
            onError?("📡 TX HEADER: MY=\(header.myCall) YOUR=\(header.yourCall) RPT1=\(header.rpt1) RPT2=\(header.rpt2)")
            onHeaderReceived?(header.myCall)
        }

        // Parse URCALL for link/unlink/info/echo commands
        let yourCall = header?.yourCall ?? ""
        // Reconstruct the raw 8-char YOUR field (with spaces) from payload offset 19-26
        let rawYourCall: String
        if payload.count >= 27 {
            rawYourCall = String(bytes: payload[(payload.startIndex + 19)..<(payload.startIndex + 27)], encoding: .ascii) ?? yourCall
        } else {
            rawYourCall = yourCall
        }
        let command = URCALLCommand.parse(rawYourCall)

        switch command {
        case .voice:
            // Normal traffic — continue to forward below
            isCommandTX = false

        case .link(let target):
            isCommandTX = true
            onError?("🔗 URCALL LINK command: \(target.type.rawValue)\(String(format: "%03d", target.number)) module \(target.module)")
            onLinkRequest?(target)
            return

        case .unlink:
            isCommandTX = true
            onError?("🔗 URCALL UNLINK command")
            onUnlinkRequest?()
            return

        case .info:
            isCommandTX = true
            onError?("🔗 URCALL INFO command")
            onInfoRequest?()
            return

        case .echo:
            isCommandTX = true
            onError?("🔗 URCALL ECHO command")
            onEchoRequest?()
            return
        }

        // Normal voice — forward to reflector
        guard let client = reflectorClient, state == .bridging else { return }

        // Rewrite RPT1/RPT2 but preserve YOUR exactly as the radio sends it.
        // The radio sends YOUR="       E" (E in position 8) — this is correct
        // for D-STAR echo test and matches what works on the OpenSPOT.
        var rewritten = Data(payload)
        let myCall = header?.myCall ?? ""

        // RPT2 at bytes 3-10, RPT1 at bytes 11-18 (per MMDVM header layout)
        let refPadded = (String(reflectorCallsign.prefix(7)).padding(toLength: 7, withPad: " ", startingAt: 0) + String(reflectorModule))
        let myPadded = (String(myCall.prefix(7)).padding(toLength: 7, withPad: " ", startingAt: 0) + String(reflectorModule))
        for (i, byte) in refPadded.utf8.prefix(8).enumerated() {
            rewritten[3 + i] = byte   // RPT2
        }
        for (i, byte) in myPadded.utf8.prefix(8).enumerated() {
            rewritten[11 + i] = byte  // RPT1
        }

        // Recalculate CRC-CCITT over bytes 0-38
        let crc = DVFrame.dstarCRC(data: rewritten, from: 0, count: 39)
        rewritten[39] = UInt8(crc & 0xFF)
        rewritten[40] = UInt8((crc >> 8) & 0xFF)

        let streamID = DExtraProtocol.randomStreamID()
        currentTXStreamID = streamID
        txFrameCounter = 0
        txVoiceForwardCount = 0

        let rpt1Str = String(bytes: rewritten[11..<19], encoding: .ascii) ?? "?"
        let rpt2Str = String(bytes: rewritten[3..<11], encoding: .ascii) ?? "?"
        onError?("📤 TX HEADER → reflector (stream=\(String(format: "%04X", streamID)) RPT1=\(rpt1Str) RPT2=\(rpt2Str) CRC=\(String(format: "%02X%02X", rewritten[39], rewritten[40])))")
        client.sendRawHeader(streamID: streamID, headerPayload: rewritten)
    }

    /// Counter for TX voice frames forwarded to the reflector.
    private var txVoiceForwardCount = 0

    /// Radio sent a voice frame — forward to network (unless this TX is a URCALL command).
    private func handleRadioVoice(_ payload: Data) {
        // Suppress forwarding for command TXs (link, unlink, info, echo)
        if isCommandTX { return }

        guard let client = reflectorClient, state == .bridging else {
            if txVoiceForwardCount == 0 {
                onError?("⚠️ TX VOICE DROPPED: client=\(reflectorClient == nil ? "nil" : "ok") state=\(state)")
            }
            return
        }
        guard let streamID = currentTXStreamID else {
            if txVoiceForwardCount == 0 {
                onError?("⚠️ TX VOICE DROPPED: no currentTXStreamID")
            }
            return
        }

        if let dvFrame = DVFrame.fromMMDVM(payload, streamID: streamID, frameCounter: txFrameCounter) {
            client.sendVoiceFrame(dvFrame)
            txVoiceForwardCount += 1
            // Log first frame and then every superframe (21 frames)
            if txVoiceForwardCount == 1 {
                let hex = payload.prefix(12).map { String(format: "%02X", $0) }.joined(separator: " ")
                onError?("📤 TX VOICE #\(txVoiceForwardCount) → reflector (stream=\(String(format: "%04X", streamID)) seq=\(txFrameCounter)) [\(hex)]")
            } else if txVoiceForwardCount % 21 == 0 {
                onError?("📤 TX VOICE #\(txVoiceForwardCount) → reflector")
            }
        } else {
            onError?("⚠️ TX VOICE: fromMMDVM returned nil (payload \(payload.count)b)")
        }

        txFrameCounter = (txFrameCounter + 1) % DExtraProtocol.framesPerSuperframe
    }

    /// Radio ended TX — send last frame to network (unless this TX was a URCALL command).
    private func handleRadioEOT() {
        // If this TX was a command, just reset the flag and skip forwarding
        if isCommandTX {
            isCommandTX = false
            currentTXStreamID = nil
            txFrameCounter = 0
            txVoiceForwardCount = 0
            return
        }

        guard let client = reflectorClient, state == .bridging else { return }
        guard let streamID = currentTXStreamID else { return }

        let lastFrame = DVFrame(
            streamID: streamID,
            frameCounter: txFrameCounter | 0x40,
            ambeData: DExtraProtocol.silenceAMBE,
            slowData: DExtraProtocol.fillerSlowData
        )
        client.sendVoiceFrame(lastFrame)
        onError?("📤 TX EOT → reflector (\(txVoiceForwardCount) voice frames sent, stream=\(String(format: "%04X", streamID)))")

        currentTXStreamID = nil
        txFrameCounter = 0
        txVoiceForwardCount = 0
    }

    // MARK: - Announcements

    /// Play a pre-recorded AMBE announcement through the radio speaker.
    /// Safe to call from any thread — dispatches to bridgeQueue.
    /// - Parameter frames: Array of 9-byte AMBE Data frames
    /// - Parameter callsign: Optional callsign for the header MY field
    func playAnnouncement(_ frames: [Data], callsign: String? = nil) {
        guard !frames.isEmpty else { return }
        guard state == .ready || state == .bridging else { return }
        // Don't interrupt active RX
        guard currentRXStreamID == nil else { return }

        bridgeQueue.async { [weak self] in
            guard let self else { return }
            self.announcementSender?.myCallsign = callsign ?? "ANNC"
            self.announcementSender?.sendAnnouncement(frames: frames, callsign: callsign)
        }
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
        networkFrameCount = 0  // reset frame counter for new transmission

        let headerFrame = MMDVMProtocol.buildDStarHeader(
            myCallsign: callsign,
            yourCallsign: "CQCQCQ  ",
            rpt1Callsign: "DIRECT  ",
            rpt2Callsign: "        "
        )
        onError?("🔊 TX HEADER → radio for \(callsign)")
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

    /// Target send time for the next voice frame (absolute nanoseconds).
    /// Using target-based pacing instead of delta-based avoids drift accumulation.
    private var nextFrameTargetTime: UInt64 = 0

    private func handleNetworkVoiceFrame(_ frame: DVFrame) {
        // Pace voice frames at 20ms intervals — the radio expects steady timing.
        // Use target-based pacing: each frame advances the target by 20ms.
        // If we fall behind (network burst), skip the sleep and catch up.
        let now = DispatchTime.now().uptimeNanoseconds
        if nextFrameTargetTime > 0 {
            if now < nextFrameTargetTime {
                // We're ahead — sleep until the target time
                let sleepNanos = nextFrameTargetTime - now
                Thread.sleep(forTimeInterval: Double(sleepNanos) / 1_000_000_000.0)
            } else if now > nextFrameTargetTime + Self.framePacingNanos * 3 {
                // We're more than 3 frames behind — reset target to avoid permanent catchup
                nextFrameTargetTime = now
            }
            // If 1-3 frames behind, just send immediately (catch up without resetting)
        }
        if nextFrameTargetTime == 0 {
            nextFrameTargetTime = DispatchTime.now().uptimeNanoseconds
        }
        nextFrameTargetTime += Self.framePacingNanos
        lastFrameSendTime = DispatchTime.now().uptimeNanoseconds

        // Convert DVFrame to MMDVM serial frame and send to radio
        let mmdvmFrame = frame.toMMDVM()
        networkFrameCount += 1
        // Log every 21st frame (once per superframe) to avoid flooding
        if networkFrameCount % 21 == 1 {
            onError?("🔊 VOICE #\(networkFrameCount) → radio")
        }
        do {
            try transport.send(mmdvmFrame)
        } catch {
            onError?("Failed to send to radio: \(error.localizedDescription)")
        }

        // If this is the last frame, send EOT to the radio
        if frame.isLastFrame {
            onError?("🔊 EOT → radio (\(networkFrameCount) frames)")
            networkFrameCount = 0
            currentRXStreamID = nil  // reset so next transmission gets a fresh header
            lastFrameSendTime = 0    // reset pacing for next transmission
            nextFrameTargetTime = 0
            let eotFrame = MMDVMProtocol.buildDStarEOT()
            do {
                try transport.send(eotFrame)
            } catch {
                onError?("Failed to send EOT to radio: \(error.localizedDescription)")
            }
        }
    }
}
