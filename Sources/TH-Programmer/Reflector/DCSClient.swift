// DCSClient.swift — DCS protocol client for DCS reflector connections

import Foundation

/// DCS protocol client — connects to DCS reflectors via UDP only (port 30051).
/// Uses POSIX sockets — NWConnection fails on macOS 26 for ad-hoc signed apps.
final class DCSClient: ReflectorClientProtocol, @unchecked Sendable {

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
    private let networkQueue = DispatchQueue(label: "com.th-programmer.dcs", qos: .userInteractive)
    private var keepaliveTimer: DispatchSourceTimer?
    private var callsign: String = ""
    private var localModule: Character = "B"
    private var remoteModule: Character = "A"
    private var host: String = ""
    private var reflectorCallsign: String = ""
    private var connectionTimeoutWork: DispatchWorkItem?
    private var registrationRetries = 0
    private let maxRegistrationRetries = 3

    // MARK: - Connect

    func connect(hostname: String, module: Character, callsign: String, localModule: Character = "B") {
        guard state == .disconnected else { return }

        self.callsign = callsign
        self.localModule = localModule
        self.remoteModule = module
        self.host = hostname
        self.reflectorCallsign = String(hostname.prefix(6)).uppercased()
        self.registrationRetries = 0
        state = .connecting

        let sock = PosixUDPSocket(queue: networkQueue)
        sock.onReceive = { [weak self] data in
            self?.handleUDPData(data)
        }
        sock.onError = { [weak self] msg in
            self?.onError?(msg)
        }

        guard sock.open(host: hostname, port: DCSProtocol.port) else {
            onError?("Failed to open UDP socket to \(hostname):\(DCSProtocol.port)")
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
            let packet = DCSProtocol.buildDisconnectPacket(callsign: callsign)
            _ = sock.send(packet)
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
        let packet = frame.serializeDCS(localCallsign: callsign, remoteModule: remoteModule)
        if !sock.send(packet) {
            onError?("DCS send error")
        }
    }

    func sendHeader(streamID: UInt16, myCallsign: String) {
        guard state == .connected, let sock = udpSocket else { return }
        let packet = DVFrame.buildDCSHeader(
            streamID: streamID,
            myCallsign: myCallsign,
            remoteModule: remoteModule
        )
        if !sock.send(packet) {
            onError?("DCS header send error")
        }
    }

    // MARK: - Registration

    private func sendRegistration() {
        guard let sock = udpSocket else { return }
        let packet = DCSProtocol.buildConnectPacket(
            callsign: callsign,
            localModule: localModule,
            remoteModule: remoteModule
        )
        if !sock.send(packet) {
            onError?("DCS registration error")
            teardown()
            return
        }

        // Retry registration if no ACK received
        networkQueue.asyncAfter(deadline: .now() + DCSProtocol.connectionTimeout) { [weak self] in
            guard let self, self.state == .registering else { return }
            if self.registrationRetries < self.maxRegistrationRetries {
                self.registrationRetries += 1
                self.sendRegistration()
            }
        }
    }

    // MARK: - Receive

    private func handleUDPData(_ data: Data) {
        guard state != .disconnected, state != .disconnecting else { return }

        let packetType = DCSProtocol.identifyPacket(data)

        switch packetType {
        case .linkAck:
            if state == .registering {
                connectionTimeoutWork?.cancel()
                connectionTimeoutWork = nil
                state = .connected
                onError?("DCS link ACK received — connected!")
                startKeepalive()
            }

        case .linkNak:
            onError?("DCS link NAK — reflector refused connection")
            teardown()

        case .control:
            if state == .registering {
                connectionTimeoutWork?.cancel()
                connectionTimeoutWork = nil
                state = .connected
                startKeepalive()
            }

        case .header:
            if let header = DVFrame.parseDCSHeader(data) {
                onHeaderReceived?(header.myCall)
            }

        case .voice:
            if let frame = DVFrame.parseDCS(data) {
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
            deadline: .now() + DCSProtocol.keepaliveInterval,
            repeating: DCSProtocol.keepaliveInterval
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
        let packet = DCSProtocol.buildPollPacket(
            callsign: callsign,
            reflectorCallsign: reflectorCallsign,
            remoteModule: remoteModule
        )
        _ = sock.send(packet)
    }
}
