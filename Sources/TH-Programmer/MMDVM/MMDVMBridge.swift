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

    private let transport: MMDVMSerialTransport
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

    // MARK: - Init

    init(transport: MMDVMSerialTransport) {
        self.transport = transport
    }

    // MARK: - Start / Stop

    /// Open the serial port and probe for MMDVM firmware.
    func start(port: RadioSerialPort) throws {
        parser.reset()
        probeRetryCount = 0
        state = .probing

        transport.onDataReceived = { [weak self] data in
            self?.bridgeQueue.async {
                self?.handleSerialData(data)
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
        detachReflector()
        transport.close()
        parser.reset()
        firmwareVersion = nil
        state = .idle
    }

    // MARK: - Serial Data Handling (radio → app)

    private func handleSerialData(_ data: Data) {
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
                // Got version — now configure the modem for D-STAR mode
                onError?("Firmware: \(version) — configuring D-STAR mode…")
                do {
                    try transport.send(MMDVMProtocol.buildSetConfig())
                    try transport.send(MMDVMProtocol.buildSetMode(mode: 0x01))
                } catch {
                    onError?("Config send failed: \(error.localizedDescription)")
                }
                state = .ready
            }

        case .ack:
            // Modem acknowledged a command
            break

        case .nak(let reason):
            onError?("MMDVM NAK: reason \(String(format: "0x%02X", reason))")

        case .status:
            // Status update — could parse modem mode flags
            break

        case .dstarHeader(let payload):
            handleRadioHeader(payload)

        case .dstarVoice(let payload):
            handleRadioVoice(payload)

        case .dstarEOT:
            handleRadioEOT()

        case .dstarLost:
            // Frame lost — could log but no action needed
            break

        case .unknown:
            break
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
    private func sendHeaderToRadio(callsign: String) {
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

    private func handleNetworkVoiceFrame(_ frame: DVFrame) {
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
            let eotFrame = MMDVMProtocol.buildDStarEOT()
            do {
                try transport.send(eotFrame)
            } catch {
                onError?("Failed to send EOT to radio: \(error.localizedDescription)")
            }
        }
    }
}
