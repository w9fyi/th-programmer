// DExtraClient.swift — DExtra protocol client for REF/XRF reflector connections

import Foundation

/// Connection state for the reflector client.
enum ReflectorConnectionState: String, Sendable {
    case disconnected
    case connecting
    case registering
    case connected
    case disconnecting
}

/// DExtra protocol client — connects to REF/XRF reflectors via UDP (port 30001).
/// Uses POSIX sockets — NWConnection fails on macOS 26 for ad-hoc signed apps.
///
/// Connection sequence:
///   1. Open UDP socket to reflector port 30001
///   2. Send link packet (11 bytes: callsign + modules)
///   3. Receive ACK (control packet ≤11 bytes)
///   4. Connected — send keepalive (9 bytes) every 5s
final class DExtraClient: ReflectorClientProtocol, @unchecked Sendable {

    nonisolated deinit {}

    // MARK: - Callbacks

    var onVoiceFrame: ((DVFrame) -> Void)?
    var onHeaderReceived: ((String) -> Void)?
    var onStateChange: ((ReflectorConnectionState) -> Void)?
    var onError: ((String) -> Void)?

    // MARK: - State

    private(set) var state: ReflectorConnectionState = .disconnected {
        didSet {
            guard state != oldValue else { return }
            onStateChange?(state)
        }
    }

    private var udpSocket: PosixUDPSocket?
    private let networkQueue = DispatchQueue(label: "com.th-programmer.dextra", qos: .userInteractive)
    private var keepaliveTimer: DispatchSourceTimer?
    private var connectionTimeoutWork: DispatchWorkItem?
    private var callsign: String = ""
    private var localModule: Character = "B"
    private var remoteModule: Character = "A"
    private var host: String = ""
    private var registrationRetries = 0
    private let maxRegistrationRetries = 3

    // MARK: - Connect

    func connect(hostname: String, module: Character, callsign: String, localModule: Character = "B") {
        guard state == .disconnected else { return }

        self.callsign = callsign
        self.localModule = localModule
        self.remoteModule = module
        self.host = hostname
        self.registrationRetries = 0
        state = .connecting

        let sock = PosixUDPSocket(queue: networkQueue)
        sock.onReceive = { [weak self] data in
            self?.handleUDPData(data)
        }
        sock.onError = { [weak self] msg in
            self?.onError?(msg)
        }

        // Use ephemeral local port — binding to 30001 causes EADDRINUSE on reconnect
        // and is not required by modern DExtra reflectors. ircDDBGateway binds 30001
        // because it's a gateway (needs a fixed port for return traffic), but clients
        // like DroidStar and BlueDV use ephemeral ports successfully.
        guard sock.open(host: hostname, port: DExtraProtocol.port) else {
            onError?("Failed to open UDP socket to \(hostname):\(DExtraProtocol.port)")
            state = .disconnected
            return
        }

        self.udpSocket = sock

        sock.startReceiving()
        state = .registering
        sendRegistration()

        // Connection timeout — 15s overall
        let timeout = DispatchWorkItem { [weak self] in
            guard let self, self.state != .connected, self.state != .disconnected else { return }
            self.onError?("Connection timed out — reflector may be offline or unreachable")
            self.teardown()
        }
        connectionTimeoutWork = timeout
        networkQueue.asyncAfter(deadline: .now() + 15.0, execute: timeout)
    }

    // MARK: - Disconnect

    func disconnect() {
        guard state != .disconnected, state != .disconnecting else { return }
        state = .disconnecting

        stopKeepalive()

        if let sock = udpSocket {
            let unlinkPacket = DExtraProtocol.buildUnlinkPacket(callsign: callsign)
            _ = sock.send(unlinkPacket)
        }

        networkQueue.asyncAfter(deadline: .now() + 0.5) { [weak self] in
            self?.teardown()
        }
    }

    private func teardown() {
        guard state != .disconnected else { return }
        connectionTimeoutWork?.cancel()
        connectionTimeoutWork = nil
        stopKeepalive()
        udpSocket?.close()
        udpSocket = nil
        state = .disconnected
    }

    // MARK: - Send Voice

    func sendVoiceFrame(_ frame: DVFrame) {
        guard state == .connected, let sock = udpSocket else { return }
        let packet = frame.serializeDExtra()
        if !sock.send(packet) {
            onError?("DExtra send error")
        }
    }

    func sendHeader(streamID: UInt16, myCallsign: String, yourCallsign: String = "CQCQCQ  ", rpt1Callsign: String = "        ", rpt2Callsign: String = "        ") {
        guard state == .connected, let sock = udpSocket else { return }
        let packet = DVFrame.buildDExtraHeader(
            streamID: streamID,
            myCallsign: myCallsign,
            yourCallsign: yourCallsign,
            rpt1Callsign: rpt1Callsign,
            rpt2Callsign: rpt2Callsign
        )
        if !sock.send(packet) {
            onError?("DExtra header send error")
        }
    }

    func sendRawHeader(streamID: UInt16, headerPayload: Data) {
        guard state == .connected, let sock = udpSocket else { return }
        let packet = DVFrame.buildDExtraHeaderFromRaw(streamID: streamID, headerPayload: headerPayload)
        if !sock.send(packet) {
            onError?("DExtra raw header send error")
        }
    }

    // MARK: - Registration

    private func sendRegistration() {
        guard let sock = udpSocket else { return }
        // For direct (non-gateway) connections, use the remote module as the
        // local module. This matches DroidStar and BlueDV behavior — a personal
        // client linking to module C sends "C" in both the local and remote
        // module positions. ircDDBGateway uses its own repeater module, but
        // that's a gateway-specific convention.
        let packet = DExtraProtocol.buildLinkPacket(
            callsign: callsign,
            module: remoteModule,
            remoteModule: remoteModule
        )
        let hex = packet.map { String(format: "%02X", $0) }.joined(separator: " ")
        onError?("DExtra link packet (\(packet.count)b): [\(hex)] call=\(callsign) local=\(remoteModule) remote=\(remoteModule)")
        if !sock.send(packet) {
            onError?("DExtra registration send error")
            teardown()
            return
        }

        // Retry registration if no ACK received
        networkQueue.asyncAfter(deadline: .now() + DExtraProtocol.connectionTimeout) { [weak self] in
            guard let self, self.state == .registering else { return }
            if self.registrationRetries < self.maxRegistrationRetries {
                self.registrationRetries += 1
                self.onError?("DExtra registration retry \(self.registrationRetries)/\(self.maxRegistrationRetries)")
                self.sendRegistration()
            }
        }
    }

    // MARK: - Receive

    private func handleUDPData(_ data: Data) {
        guard state != .disconnected, state != .disconnecting else { return }

        let packetType = DExtraProtocol.identifyPacket(data)

        // Diagnostic: log every packet
        let hex = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
        onError?("rx \(state): \(data.count)b [\(hex)] → \(packetType)")

        switch packetType {
        case .linkAck:
            if state == .registering {
                connectionTimeoutWork?.cancel()
                connectionTimeoutWork = nil
                state = .connected
                onError?("Link ACK received — connected!")
                startKeepalive()
            }

        case .linkNak:
            onError?("Link NAK — reflector refused connection (echoed packet unchanged)")
            teardown()

        case .keepalive:
            break

        case .unlink:
            onError?("Reflector sent unlink")
            teardown()

        case .header:
            if let header = DVFrame.parseDExtraHeader(data) {
                onHeaderReceived?(header.myCall)
            }

        case .voice:
            if let frame = DVFrame.parseDExtra(data) {
                onVoiceFrame?(frame)
            }

        case .unknown:
            break
        }
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        stopKeepalive()
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(
            deadline: .now() + DExtraProtocol.keepaliveInterval,
            repeating: DExtraProtocol.keepaliveInterval
        )
        timer.setEventHandler { [weak self] in
            self?.sendKeepalive()
        }
        keepaliveTimer = timer
        timer.resume()
    }

    private func stopKeepalive() {
        keepaliveTimer?.cancel()
        keepaliveTimer = nil
    }

    private func sendKeepalive() {
        guard state == .connected, let sock = udpSocket else { return }
        let packet = DExtraProtocol.buildKeepalivePacket(callsign: callsign)
        _ = sock.send(packet)
    }
}
