// DPlusClient.swift — DPlus protocol client for REF reflector connections

import Foundation

/// DPlus protocol client — connects to REF reflectors via UDP (port 20001).
/// Uses POSIX sockets — NWConnection fails on macOS 26 for ad-hoc signed apps.
///
/// Connection sequence:
///   1. Send CT_LINK1 (5 bytes)
///   2. Receive CT_LINK1 echo
///   3. Send CT_LINK2 login (28 bytes with callsign)
///   4. Receive ACK (8 bytes "OKRW") or NAK ("BUSY")
///   5. Connected — send keepalive (3 bytes) every 1s
final class DPlusClient: ReflectorClientProtocol, @unchecked Sendable {

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
    private let networkQueue = DispatchQueue(label: "com.th-programmer.dplus", qos: .userInteractive)
    private var keepaliveTimer: DispatchSourceTimer?
    private var connectionTimeoutWork: DispatchWorkItem?
    private var callsign: String = ""
    private var localModule: Character = "B"
    private var remoteModule: Character = "A"
    private var host: String = ""

    /// Tracks the handshake phase within the .registering state.
    private enum HandshakePhase {
        case awaitingConnectEcho   // sent CT_LINK1, waiting for echo
        case awaitingLoginAck      // sent CT_LINK2, waiting for ACK/NAK
    }
    private var handshakePhase: HandshakePhase = .awaitingConnectEcho

    // MARK: - Connect

    func connect(hostname: String, module: Character, callsign: String, localModule: Character = "B") {
        guard state == .disconnected else { return }

        self.callsign = callsign
        self.localModule = localModule
        self.remoteModule = module
        self.host = hostname
        self.handshakePhase = .awaitingConnectEcho
        state = .connecting

        let sock = PosixUDPSocket(queue: networkQueue)
        sock.onReceive = { [weak self] data in
            self?.handleUDPData(data)
        }
        sock.onError = { [weak self] msg in
            self?.onError?(msg)
        }

        guard sock.open(host: hostname, port: DPlusProtocol.port) else {
            onError?("Failed to open UDP socket to \(hostname):\(DPlusProtocol.port)")
            state = .disconnected
            return
        }

        self.udpSocket = sock

        // Start receiving, then send handshake
        sock.startReceiving()
        state = .registering
        handshakePhase = .awaitingConnectEcho
        sendConnect()

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
            // DPlus convention: send disconnect twice for reliability
            let packet = DPlusProtocol.buildDisconnectPacket()
            _ = sock.send(packet)
            _ = sock.send(packet)
        }

        // Brief delay then teardown
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
        let packet = frame.serializeDPlus()
        if !sock.send(packet) {
            onError?("DPlus send error")
        }
    }

    func sendHeader(streamID: UInt16, myCallsign: String) {
        guard state == .connected, let sock = udpSocket else { return }
        let packet = DVFrame.buildDPlusHeader(
            streamID: streamID,
            myCallsign: myCallsign,
            remoteModule: remoteModule
        )
        if !sock.send(packet) {
            onError?("DPlus header send error")
        }
    }

    // MARK: - Handshake

    private func sendConnect() {
        guard let sock = udpSocket else { return }
        let packet = DPlusProtocol.buildConnectPacket()
        if !sock.send(packet) {
            onError?("DPlus connect send error")
            teardown()
        }
    }

    private func sendLogin() {
        guard let sock = udpSocket else { return }
        let packet = DPlusProtocol.buildLoginPacket(callsign: callsign)
        if !sock.send(packet) {
            onError?("DPlus login send error")
            teardown()
        }
    }

    // MARK: - Receive

    private func handleUDPData(_ data: Data) {
        guard state != .disconnected, state != .disconnecting else { return }

        let packetType = DPlusProtocol.identifyPacket(data)

        // Diagnostic: report every packet
        let hex = data.prefix(16).map { String(format: "%02X", $0) }.joined(separator: " ")
        onError?("rx \(state): \(data.count)b [\(hex)] → \(packetType)")

        switch packetType {
        case .connectEcho:
            if state == .registering, handshakePhase == .awaitingConnectEcho {
                onError?("Connect echo received — sending login")
                handshakePhase = .awaitingLoginAck
                sendLogin()
            }

        case .loginAck:
            if state == .registering, handshakePhase == .awaitingLoginAck {
                onError?("Login accepted")
                connectionTimeoutWork?.cancel()
                connectionTimeoutWork = nil
                state = .connected
                startKeepalive()
            }

        case .loginNack:
            onError?("REF login refused — callsign may not be registered or reflector is busy")
            teardown()

        case .disconnect:
            onError?("Reflector sent disconnect")
            teardown()

        case .keepalive:
            break

        case .header:
            if let header = DVFrame.parseDPlusHeader(data) {
                onHeaderReceived?(header.myCall)
            }

        case .voice:
            if let frame = DVFrame.parseDPlus(data) {
                onVoiceFrame?(frame)
            }

        case .lastVoice:
            if let frame = DVFrame.parseDPlus(data) {
                onVoiceFrame?(frame)
            }

        case .unknown:
            break
        }
    }

    // MARK: - Keepalive

    private func startKeepalive() {
        onError?("Starting keepalive timer (every \(DPlusProtocol.keepaliveInterval)s)")
        stopKeepalive()
        let timer = DispatchSource.makeTimerSource(queue: networkQueue)
        timer.schedule(
            deadline: .now() + DPlusProtocol.keepaliveInterval,
            repeating: DPlusProtocol.keepaliveInterval
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
        let packet = DPlusProtocol.buildKeepalivePacket()
        _ = sock.send(packet)
    }
}
