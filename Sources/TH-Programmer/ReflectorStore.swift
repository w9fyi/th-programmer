// ReflectorStore.swift — ViewModel for the D-STAR reflector gateway

import SwiftUI
import AppKit
import CoreAudio
import IOBluetooth

/// Manages the D-STAR reflector internet gateway — supports two modes:
/// 1. Software Codec: mbelib on Mac, AVAudioEngine for audio I/O
/// 2. MMDVM Terminal: TH-D75 in terminal mode handles codec + audio, app bridges serial ↔ network
@MainActor
final class ReflectorStore: ObservableObject {

    nonisolated deinit {}

    // MARK: - Published State

    @Published var connectionState: ReflectorConnectionState = .disconnected
    @Published var connectedReflector: ReflectorTarget?
    @Published var heardStations: [HeardStation] = []
    @Published var isPTT: Bool = false
    @Published var myCallsign: String = ""
    @Published var statusMessage: String = "Not connected"
    @Published var errorMessage: String?
    @Published var connectionLog: [String] = []
    @Published var rxLevel: Float = 0.0
    @Published var txLevel: Float = 0.0
    @Published var rxSlowDataText: String = ""
    @Published var rxGPSPosition: String = ""

    // TX timeout
    @Published var txTimeoutSeconds: Int = 180
    @Published var txTimeRemaining: Int = 0

    // Audio devices (software mode)
    @Published var availableInputDevices: [AudioDevice] = []
    @Published var availableOutputDevices: [AudioDevice] = []
    @Published var selectedInputDeviceID: AudioDeviceID?
    @Published var selectedOutputDeviceID: AudioDeviceID?

    // Audio source routing
    @Published var audioSourceMode: AudioSourceMode = .macDefault
    @Published var radioUSBAvailable: Bool = false
    @Published var radioBluetoothAvailable: Bool = false

    // Bluetooth — shared with RadioStore to avoid two managers fighting
    // over the same RFCOMM channel. Injected via init(bluetooth:).
    @Published var bluetoothManager: BluetoothManager
    @Published var isBluetoothScanning: Bool = false

    // Favorites
    @Published var favoritesManager = FavoritesManager()

    // UI state (sheets)
    @Published var showDirectory: Bool = false
    @Published var showAddFavoriteFromMenu: Bool = false

    // Gateway mode
    @Published var gatewayMode: GatewayMode = .software

    // MMDVM / Terminal Mode state
    @Published var availableSerialPorts: [RadioSerialPort] = []
    @Published var selectedSerialPort: RadioSerialPort?
    @Published var mmdvmState: MMDVMBridge.BridgeState = .idle
    @Published var mmdvmFirmwareVersion: String?

    /// The Bluetooth radio selected for direct RFCOMM transport (nil = use serial port).
    @Published var selectedBluetoothRadio: BluetoothRadio?

    /// Whether the current MMDVM connection uses direct RFCOMM (true) or serial port (false).
    @Published private(set) var isDirectRFCOMM: Bool = false

    // MARK: - Internal Components

    /// App Nap prevention token — keeps the process at full priority during
    /// active gateway operation so 20ms voice frame pacing isn't disrupted.
    private var appNapActivity: NSObjectProtocol?

    private var reflectorClient: ReflectorClientProtocol?
    private let codec = AMBECodec()
    private let slowDataDecoder = SlowDataDecoder()
    private let audioEngine = AudioEngine()
    private let deviceManager = AudioDeviceManager()
    private let hostLookup = ReflectorHostLookup.shared
    private let codecQueue = DispatchQueue(label: "com.th-programmer.reflector-codec", qos: .userInteractive)

    // MMDVM components
    private var mmdvmTransport: (any MMDVMTransport)?
    private var mmdvmBridge: MMDVMBridge?

    // Terminal mode client (TH-D75 in Reflector TERM Mode)
    private var terminalModeClient: TerminalModeClient?

    // TX timeout timer
    private var txTimeoutTimer: Timer?

    /// Current stream ID for TX (nil when not transmitting).
    /// Accessed from codecQueue — not @MainActor isolated.
    private nonisolated(unsafe) var txStreamID: UInt16?
    private nonisolated(unsafe) var txFrameCounter: UInt8 = 0

    /// Track the current RX stream to detect new transmissions.
    private var currentRXStreamID: UInt16?

    /// Maximum heard stations to keep in the list.
    private let maxHeardStations = 50

    // MARK: - Init

    /// Initialize with a shared BluetoothManager (from RadioStore) to avoid
    /// two managers competing for the same RFCOMM channel on the radio.
    init(bluetooth: BluetoothManager? = nil) {
        self.bluetoothManager = bluetooth ?? BluetoothManager()

        setupAudioEngine()
        refreshDevices()

        // Load cached reflector hosts from disk, then fetch fresh from network
        hostLookup.loadFromDisk()
        hostLookup.ensureLoaded()

        deviceManager.onDevicesChanged = { [weak self] in
            Task { @MainActor in
                self?.refreshDevices()
            }
        }

        // Only start monitoring if we own the manager (no shared one provided).
        // When shared, RadioStore already handles discovery and monitoring.
        if bluetooth == nil {
            bluetoothManager.startMonitoringConnections()
            bluetoothManager.refreshPaired()
        }

        bluetoothManager.onRadioConnected = { [weak self] radio in
            Task { @MainActor in
                guard let self else { return }
                self.selectedBluetoothRadio = radio
                self.refreshDevices()
                if self.audioSourceMode == .radioBluetooth, self.radioBluetoothAvailable {
                    self.applyAudioSourceMode(.radioBluetooth)
                    self.announceAccessibility("TH-D75 Bluetooth audio connected")
                }
            }
        }
    }

    // MARK: - Device Management

    func refreshDevices() {
        availableInputDevices = deviceManager.inputDevices()
        availableOutputDevices = deviceManager.outputDevices()

        if selectedInputDeviceID == nil {
            selectedInputDeviceID = deviceManager.defaultInputDevice()
        }
        if selectedOutputDeviceID == nil {
            selectedOutputDeviceID = deviceManager.defaultOutputDevice()
        }

        // Update radio audio availability
        let hadUSB = radioUSBAvailable
        radioUSBAvailable = deviceManager.radioUSBInputDevice() != nil
            || deviceManager.radioUSBOutputDevice() != nil
        radioBluetoothAvailable = deviceManager.radioBluetoothInputDevice() != nil
            || deviceManager.radioBluetoothOutputDevice() != nil

        // Auto-select radio devices when mode matches and device just appeared
        if audioSourceMode == .radioUSB, radioUSBAvailable, !hadUSB {
            applyAudioSourceMode(.radioUSB)
            announceAccessibility("TH-D75 USB audio detected")
        }
    }

    func setInputDevice(_ deviceID: AudioDeviceID) {
        selectedInputDeviceID = deviceID
    }

    func setOutputDevice(_ deviceID: AudioDeviceID) {
        selectedOutputDeviceID = deviceID
        if connectionState == .connected, gatewayMode == .software {
            try? audioEngine.startPlayback(outputDeviceID: deviceID)
        }
    }

    // MARK: - Audio Source Mode

    func setAudioSourceMode(_ mode: AudioSourceMode) {
        audioSourceMode = mode
        applyAudioSourceMode(mode)
    }

    private func applyAudioSourceMode(_ mode: AudioSourceMode) {
        switch mode {
        case .macDefault:
            selectedInputDeviceID = deviceManager.defaultInputDevice()
            selectedOutputDeviceID = deviceManager.defaultOutputDevice()

        case .radioUSB:
            if let input = deviceManager.radioUSBInputDevice() {
                selectedInputDeviceID = input.id
            }
            if let output = deviceManager.radioUSBOutputDevice() {
                selectedOutputDeviceID = output.id
            }

        case .radioBluetooth:
            if let input = deviceManager.radioBluetoothInputDevice() {
                selectedInputDeviceID = input.id
            }
            if let output = deviceManager.radioBluetoothOutputDevice() {
                selectedOutputDeviceID = output.id
            }
        }

        // If connected and playing, restart with new output device
        if connectionState == .connected, gatewayMode == .software,
           let outputID = selectedOutputDeviceID {
            try? audioEngine.startPlayback(outputDeviceID: outputID)
        }
    }

    // MARK: - Bluetooth

    func scanBluetooth() {
        bluetoothManager.startScan()
    }

    func stopBluetoothScan() {
        bluetoothManager.stopScan()
    }

    func connectBluetooth(_ radio: BluetoothRadio) {
        // Store the radio for direct RFCOMM transport selection
        selectedBluetoothRadio = radio

        // In MMDVM terminal mode, DON'T open the Bluetooth connection here.
        // connectMMDVM() handles the full Bluetooth lifecycle itself, and if we
        // connect here first, the radio hears two "connection completed" events
        // which corrupts terminal mode state (radio enters SPP instead of MMDVM).
        // Just record the selection and let connectMMDVM do the work.
        if gatewayMode == .mmdvmTerminal {
            announceAccessibility("Radio selected. Press Connect MMDVM to connect.")
            return
        }

        Task {
            let path = await bluetoothManager.connect(radio)
            refreshDevices()
            // Refresh serial ports so the new BT port appears in the MMDVM picker
            refreshSerialPorts()
            // Auto-select the new BT port if one appeared (fallback if direct RFCOMM fails)
            if let path, selectedSerialPort == nil {
                selectedSerialPort = availableSerialPorts.first { $0.path == path }
            }
            if radioBluetoothAvailable, audioSourceMode == .radioBluetooth {
                applyAudioSourceMode(.radioBluetooth)
            }
        }
    }

    // MARK: - Favorites

    func addFavorite(label: String) {
        guard let target = connectedReflector else { return }
        favoritesManager.add(target: target, label: label)
    }

    func removeFavorite(id: UUID) {
        favoritesManager.remove(id: id)
    }

    func connectToFavorite(_ favorite: ReflectorFavorite) {
        connect(to: favorite.target)
    }

    // MARK: - Serial Port Management

    func refreshSerialPorts() {
        availableSerialPorts = SerialPortDiscovery.discover()
        if selectedSerialPort == nil, let best = availableSerialPorts.first {
            selectedSerialPort = best
        }
    }

    // MARK: - MMDVM Connect / Disconnect

    func connectMMDVM() {
        // Guard against double-connect — only allow from idle or error states
        switch mmdvmState {
        case .idle, .error:
            break  // OK to connect
        case .probing, .ready, .bridging, .reconnecting:
            return  // already connecting or connected
        }

        // Diagnostic log to Desktop
        let logPath = "/Users/justinmann/Desktop/rfcomm_connect.log"
        func diagLog(_ msg: String) {
            let line = "\(ISO8601DateFormatter().string(from: Date())) \(msg)\n"
            if let data = line.data(using: .utf8) {
                if FileManager.default.fileExists(atPath: logPath) {
                    if let h = FileHandle(forWritingAtPath: logPath) {
                        h.seekToEndOfFile(); h.write(data); h.closeFile()
                    }
                } else {
                    FileManager.default.createFile(atPath: logPath, contents: data)
                }
            }
        }

        // Stop any existing bridge before creating a new one
        mmdvmBridge?.stop()
        mmdvmBridge = nil
        mmdvmTransport = nil

        diagLog("=== connectMMDVM() called ===")
        diagLog("selectedBluetoothRadio: \(selectedBluetoothRadio?.name ?? "nil") addr=\(selectedBluetoothRadio?.addressString ?? "nil")")
        diagLog("bluetoothManager.radios count: \(bluetoothManager.radios.count)")
        for (i, r) in bluetoothManager.radios.enumerated() {
            diagLog("  radio[\(i)]: \(r.name) addr=\(r.addressString) connected=\(r.isConnected) port=\(r.portPath ?? "nil")")
        }
        diagLog("selectedSerialPort: \(selectedSerialPort?.path ?? "nil")")

        // Choose transport: direct RFCOMM for Bluetooth, POSIX serial for USB
        let transport: any MMDVMTransport
        let port: RadioSerialPort
        let useDirectRFCOMM: Bool

        // If no BT radio explicitly selected, auto-select the first paired one
        if selectedBluetoothRadio == nil,
           let firstPaired = bluetoothManager.radios.first {
            selectedBluetoothRadio = firstPaired
            diagLog("Auto-selected BT radio: \(firstPaired.name) addr=\(firstPaired.addressString)")
        }

        if let btRadio = selectedBluetoothRadio,
           btRadio.addressString != "detected-from-dev" {
            diagLog("Taking DIRECT RFCOMM path for \(btRadio.addressString)")
            // Release BluetoothManager's held RFCOMM channel so RFCOMMTransport
            // can open channel 2 directly. The radio only supports one RFCOMM session.
            let hadChannel = bluetoothManager.rfcommChannel != nil
            bluetoothManager.releaseRFCOMMChannel()
            diagLog("Released BluetoothManager RFCOMM channel (had=\(hadChannel))")

            // Direct RFCOMM — bypass virtual serial port
            let rfcomm = RFCOMMTransport(address: btRadio.addressString)
            transport = rfcomm
            port = rfcomm.syntheticPort
            useDirectRFCOMM = true
        } else if let serialPort = selectedSerialPort {
            diagLog("Taking SERIAL PORT path: \(serialPort.path)")
            // POSIX serial — USB CDC or fallback BT serial port
            transport = MMDVMSerialTransport()
            port = serialPort
            useDirectRFCOMM = false
        } else {
            diagLog("ERROR: No serial port or Bluetooth radio available")
            errorMessage = "No serial port or Bluetooth radio selected"
            return
        }

        let bridge = MMDVMBridge(transport: transport)

        bridge.onStateChange = { [weak self] newState in
            diagLog("Bridge state: \(newState)")
            Task { @MainActor in
                guard let self else { return }
                self.mmdvmState = newState

                switch newState {
                case .ready:
                    self.mmdvmFirmwareVersion = bridge.firmwareVersion
                    self.statusMessage = "Radio ready — \(bridge.firmwareVersion ?? "unknown")"
                    self.announceAccessibility("Radio connected. \(bridge.firmwareVersion ?? "").")
                case .bridging:
                    self.statusMessage = "Bridging active"
                    self.announceAccessibility("Bridging active — radio and reflector connected")
                case .error(let msg):
                    self.errorMessage = msg
                    self.statusMessage = msg
                    self.announceAccessibility(msg)
                case .reconnecting(let attempt):
                    self.statusMessage = "Reconnecting to radio (\(attempt)/10)…"
                    self.announceAccessibility("Reconnecting to radio, attempt \(attempt)")
                case .idle, .probing:
                    break
                }
            }
        }

        bridge.onHeaderReceived = { [weak self] callsign in
            Task { @MainActor in
                self?.addHeardStation(callsign: callsign)
            }
        }

        bridge.onError = { [weak self] message in
            diagLog("Bridge error: \(message)")
            Task { @MainActor in
                self?.connectionLog.append("[mmdvm] \(message)")
            }
        }

        // URCALL command callbacks — link/unlink/info/echo from the radio
        bridge.onLinkRequest = { [weak self] target in
            Task { @MainActor in
                guard let self else { return }
                self.connectionLog.append("[urcall] Link request: \(target.type.rawValue)\(String(format: "%03d", target.number)) module \(target.module)")
                self.announceAccessibility("Link request: \(target.type.rawValue)\(String(format: "%03d", target.number)) module \(target.module)")
                // Play "linking" announcement
                if let player = bridge.announcementPlayer {
                    let frames = player.linkingAnnouncement()
                    bridge.playAnnouncement(frames, callsign: self.myCallsign)
                }
                // Disconnect current if connected
                if self.connectionState != .disconnected {
                    self.disconnect()
                    // Brief delay for clean disconnect
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
                self.connect(to: target)
            }
        }

        bridge.onUnlinkRequest = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.connectionLog.append("[urcall] Unlink request")
                self.announceAccessibility("Unlink request")
                self.disconnect()
                // Play "not linked" announcement after disconnect
                if let player = bridge.announcementPlayer {
                    let frames = player.unlinkedAnnouncement()
                    bridge.playAnnouncement(frames, callsign: self.myCallsign)
                }
            }
        }

        bridge.onInfoRequest = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                let info: String
                if let target = self.connectedReflector {
                    info = "Connected to \(target.type.rawValue)\(String(format: "%03d", target.number)) module \(target.module)"
                    // Play linked announcement with reflector details
                    if let player = bridge.announcementPlayer {
                        let frames = player.linkedAnnouncement(
                            type: target.type.rawValue,
                            number: target.number,
                            module: target.module
                        )
                        bridge.playAnnouncement(frames, callsign: self.myCallsign)
                    }
                } else {
                    info = "Not connected to any reflector"
                    // Play "not linked" announcement
                    if let player = bridge.announcementPlayer {
                        let frames = player.unlinkedAnnouncement()
                        bridge.playAnnouncement(frames, callsign: self.myCallsign)
                    }
                }
                self.connectionLog.append("[urcall] Info request: \(info)")
                self.announceAccessibility(info)
            }
        }

        bridge.onEchoRequest = { [weak self] in
            Task { @MainActor in
                guard let self else { return }
                self.connectionLog.append("[urcall] Echo test request")
                self.announceAccessibility("Echo test requested")
            }
        }

        self.mmdvmTransport = transport
        self.mmdvmBridge = bridge
        self.isDirectRFCOMM = useDirectRFCOMM

        if useDirectRFCOMM {
            statusMessage = "Connecting via direct RFCOMM to \(port.displayName)…"
            connectionLog.append("Opening direct RFCOMM channel 2 to \(port.displayName)")
        } else {
            statusMessage = "Connecting to radio on \(port.displayName)…"
            connectionLog.append("Opening \(port.path) at 38400 baud (MMDVM protocol)")
        }
        announceAccessibility(statusMessage)

        // Run on a background thread — IOBluetooth needs the main run loop
        // free to process Bluetooth events during openConnection/openRFCOMMChannelSync.
        let startPort = port
        let startBridge = bridge
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            do {
                try startBridge.start(port: startPort)
            } catch {
                Task { @MainActor in
                    self?.errorMessage = "Failed to connect: \(error.localizedDescription)"
                    self?.mmdvmTransport = nil
                    self?.mmdvmBridge = nil
                }
            }
        }
    }

    func disconnectMMDVM() {
        mmdvmBridge?.stop()
        mmdvmBridge = nil
        mmdvmTransport = nil
        isDirectRFCOMM = false
        selectedBluetoothRadio = nil
        terminalModeClient?.disconnect()
        terminalModeClient = nil
        mmdvmState = .idle
        mmdvmFirmwareVersion = nil
        statusMessage = "Radio disconnected"
        announceAccessibility("Radio disconnected")
    }

    // MARK: - Reflector Connect / Disconnect

    func connect(to target: ReflectorTarget) {
        guard connectionState == .disconnected else { return }
        guard target.isValid else {
            errorMessage = "Invalid reflector target"
            return
        }
        guard !myCallsign.trimmingCharacters(in: .whitespaces).isEmpty else {
            errorMessage = "Enter your callsign before connecting"
            return
        }

        // In terminal mode, radio must be connected
        if gatewayMode == .mmdvmTerminal {
            guard terminalModeClient?.state == .connected ||
                  mmdvmState == .ready || mmdvmState == .bridging else {
                errorMessage = "Connect to radio first"
                return
            }
        }

        connectedReflector = target
        connectionLog = []
        favoritesManager.updateLastUsed(target: target)

        // Helper to write connection events to both UI log and diagnostic file
        func connLog(_ msg: String) {
            connectionLog.append(msg)
            let line = "\(ISO8601DateFormatter().string(from: Date())) Connect: \(msg)\n"
            if let data = line.data(using: .utf8),
               let h = FileHandle(forWritingAtPath: "/Users/justinmann/Desktop/rfcomm_connect.log") {
                h.seekToEndOfFile(); h.write(data); h.closeFile()
            }
        }

        // Create the appropriate reflector client
        let client = makeReflectorClient(for: target)
        self.reflectorClient = client
        setupClientCallbacks(client)

        // Resolve hostname from official host files, fall back to generated hostname
        let reflectorName = "\(target.type.rawValue)\(String(format: "%03d", target.number))"

        // For REF targets, always authenticate with DPlus trust server first.
        // DPlus auth registers our callsign+IP with the trust system — without it,
        // reflectors silently discard our packets.
        // XRF/XLX use DExtra protocol which doesn't require DPlus auth.
        if target.type == .ref {
            // Always authenticate with the DPlus trust server before connecting.
            // The TCP auth registers our callsign+IP with the trust system.
            // Without fresh auth, the reflector may accept login but silently
            // discard voice from unregistered IPs.
            statusMessage = "Authenticating with DPlus trust server…"
            connLog(statusMessage)
            announceAccessibility(statusMessage)

            hostLookup.authenticateDPlus(callsign: myCallsign, diagnostic: { [weak self] msg in
                Task { @MainActor in
                    self?.connectionLog.append("[auth] \(msg)")
                    let line = "\(ISO8601DateFormatter().string(from: Date())) Connect: [auth] \(msg)\n"
                    if let data = line.data(using: .utf8),
                       let h = FileHandle(forWritingAtPath: "/Users/justinmann/Desktop/rfcomm_connect.log") {
                        h.seekToEndOfFile(); h.write(data); h.closeFile()
                    }
                }
            }) { [weak self] count in
                guard let self else { return }
                connLog("DPlus auth returned \(count) reflector IPs")
                if let ip = self.hostLookup.lookup(target: target),
                   ReflectorHostLookup.isIPAddress(ip) {
                    connLog("Resolved \(reflectorName) → \(ip)")
                    self.performConnect(client: client, target: target, hostname: ip, reflectorName: reflectorName)
                } else if let hostname = self.hostLookup.lookup(target: target), !hostname.isEmpty {
                    connLog("Auth failed — falling back to hostname \(hostname)")
                    self.performConnect(client: client, target: target, hostname: hostname, reflectorName: reflectorName)
                } else {
                    let fallback = ReflectorHostLookup.fallbackHostname(type: target.type, number: target.number)
                    connLog("Auth failed, no host file entry — trying fallback \(fallback)")
                    self.performConnect(client: client, target: target, hostname: fallback, reflectorName: reflectorName)
                }
            }
            return
        }

        let hostname: String
        if let resolved = hostLookup.lookup(target: target) {
            hostname = resolved
            connLog("Resolved \(reflectorName) → \(hostname)")
        } else {
            hostname = ReflectorHostLookup.fallbackHostname(type: target.type, number: target.number)
            connLog("Host file lookup miss for \(reflectorName) — using fallback \(hostname)")
        }

        performConnect(client: client, target: target, hostname: hostname, reflectorName: reflectorName)
    }

    /// Actually initiate the network connection after hostname resolution.
    private func performConnect(client: ReflectorClientProtocol, target: ReflectorTarget, hostname: String, reflectorName: String) {
        let port: UInt16
        switch target.type {
        case .ref: port = DPlusProtocol.port
        case .dcs: port = DCSProtocol.port
        case .xrf, .xlx: port = DExtraProtocol.port
        }
        statusMessage = "Connecting to \(reflectorName) module \(target.module) via \(hostname):\(port)…"
        connectionLog.append(statusMessage)
        announceAccessibility(statusMessage)

        client.connect(
            hostname: hostname,
            module: target.module,
            callsign: myCallsign,
            localModule: "B"
        )
    }

    func disconnect() {
        guard connectionState != .disconnected else { return }

        if gatewayMode == .mmdvmTerminal {
            mmdvmBridge?.detachReflector()
        } else {
            stopTransmit()
            codec.reset()
        }

        reflectorClient?.disconnect()
        statusMessage = "Disconnecting…"
        announceAccessibility("Disconnecting from reflector")
    }

    // MARK: - PTT (Software mode only)

    func startTransmit() {
        guard gatewayMode == .software else { return }
        guard connectionState == .connected, !isPTT else { return }
        isPTT = true

        let streamID = DExtraProtocol.randomStreamID()
        txStreamID = streamID
        txFrameCounter = 0

        reflectorClient?.sendHeader(streamID: streamID, myCallsign: myCallsign, yourCallsign: "CQCQCQ  ", rpt1Callsign: "        ", rpt2Callsign: "        ")

        do {
            try audioEngine.startCapture(inputDeviceID: selectedInputDeviceID)
        } catch {
            errorMessage = "Failed to start audio capture: \(error.localizedDescription)"
            isPTT = false
            return
        }

        statusMessage = "Transmitting"
        announceAccessibility("Transmitting")

        // Start TX timeout timer
        txTimeRemaining = txTimeoutSeconds
        txTimeoutTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            Task { @MainActor in
                guard let self, self.isPTT else { return }
                self.txTimeRemaining -= 1
                if self.txTimeRemaining <= 0 {
                    self.stopTransmit()
                    self.announceAccessibility("Transmit timeout")
                }
            }
        }
    }

    func stopTransmit() {
        guard isPTT else { return }
        isPTT = false

        txTimeoutTimer?.invalidate()
        txTimeoutTimer = nil
        txTimeRemaining = 0

        if let streamID = txStreamID {
            let lastFrame = DVFrame(
                streamID: streamID,
                frameCounter: txFrameCounter | 0x40,
                ambeData: DExtraProtocol.silenceAMBE,
                slowData: DExtraProtocol.fillerSlowData
            )
            reflectorClient?.sendVoiceFrame(lastFrame)
        }

        txStreamID = nil
        txFrameCounter = 0
        audioEngine.stopCapture()

        statusMessage = "Connected"
        announceAccessibility("Transmit ended")
    }

    func togglePTT() {
        if isPTT {
            stopTransmit()
        } else {
            startTransmit()
        }
    }

    // MARK: - Client Factory

    private func makeReflectorClient(for target: ReflectorTarget) -> ReflectorClientProtocol {
        switch target.type {
        case .ref:
            return DPlusClient()
        case .dcs:
            return DCSClient()
        case .xrf, .xlx:
            return DExtraClient()
        }
    }

    // MARK: - Client Callbacks

    private func setupClientCallbacks(_ client: ReflectorClientProtocol) {
        client.onStateChange = { [weak self] newState in
            Task { @MainActor in
                guard let self else { return }
                self.connectionState = newState

                switch newState {
                case .connected:
                    self.statusMessage = "Connected"
                    self.announceAccessibility("Connected to reflector")

                    // Prevent App Nap from throttling voice frame pacing
                    self.appNapActivity = ProcessInfo.processInfo.beginActivity(
                        options: [.userInitiated, .latencyCritical],
                        reason: "D-STAR reflector gateway — 20ms voice frame pacing"
                    )

                    if self.gatewayMode == .mmdvmTerminal {
                        // Set reflector identity for header RPT1/RPT2 fields
                        if let target = self.connectedReflector {
                            let name = "\(target.type.rawValue)\(String(format: "%03d", target.number))"
                            self.mmdvmBridge?.reflectorCallsign = name
                            self.mmdvmBridge?.reflectorModule = target.module
                        }
                        // Play "linked" announcement BEFORE attaching reflector
                        // so the announcement doesn't compete with incoming traffic
                        if let target = self.connectedReflector,
                           let player = self.mmdvmBridge?.announcementPlayer {
                            let frames = player.linkedAnnouncement(
                                type: target.type.rawValue,
                                number: target.number,
                                module: target.module
                            )
                            self.mmdvmBridge?.playAnnouncement(frames, callsign: self.myCallsign)
                        }
                        // Attach reflector to MMDVM bridge
                        self.mmdvmBridge?.attachReflector(client)
                    } else {
                        try? self.audioEngine.startPlayback(outputDeviceID: self.selectedOutputDeviceID)
                        // Prepare capture engine now so the TCC mic prompt happens once,
                        // not on every PTT press.
                        try? self.audioEngine.prepareCaptureEngine(inputDeviceID: self.selectedInputDeviceID)
                    }

                case .disconnected:
                    // Play "not linked" announcement before clearing state
                    // (bridge must still be ready/bridging to send)
                    if self.gatewayMode == .mmdvmTerminal,
                       let player = self.mmdvmBridge?.announcementPlayer {
                        let frames = player.unlinkedAnnouncement()
                        self.mmdvmBridge?.playAnnouncement(frames, callsign: self.myCallsign)
                    }

                    self.statusMessage = "Disconnected"
                    self.connectedReflector = nil
                    self.currentRXStreamID = nil
                    self.reflectorClient = nil

                    // Allow App Nap again
                    self.appNapActivity = nil
                    if self.gatewayMode == .software {
                        self.audioEngine.stopPlayback()
                        self.audioEngine.teardownCaptureEngine()
                    }
                    self.announceAccessibility("Disconnected")

                case .connecting:
                    self.statusMessage = "Connecting…"

                case .registering:
                    self.statusMessage = "Registering…"

                case .disconnecting:
                    self.statusMessage = "Disconnecting…"
                }
            }
        }

        // Only wire codec callbacks in software mode
        if gatewayMode == .software {
            client.onVoiceFrame = { [weak self] frame in
                guard let self else { return }
                self.codecQueue.async {
                    guard let samples = self.codec.decode(ambeBytes: frame.ambeData) else { return }
                    self.audioEngine.enqueueForPlayback(samples)

                    // Decode slow data
                    let decoded = self.slowDataDecoder.feed(
                        slowData: frame.slowData,
                        frameCounter: frame.frameCounter & 0x1F  // mask off end-of-stream bit
                    )

                    Task { @MainActor in
                        self.rxLevel = self.audioEngine.rxLevel
                        if let decoded {
                            if !decoded.textMessage.isEmpty {
                                self.rxSlowDataText = decoded.textMessage
                            }
                            if !decoded.gpsPosition.isEmpty {
                                self.rxGPSPosition = decoded.gpsPosition
                            }
                        }
                    }
                }
            }
        }
        // In MMDVM mode, onVoiceFrame is set by MMDVMBridge.attachReflector()

        client.onHeaderReceived = { [weak self] callsign in
            Task { @MainActor in
                self?.addHeardStation(callsign: callsign)
            }
        }

        client.onError = { [weak self] message in
            // Also write to diagnostic file log so we can see DPlus/DExtra/DCS events
            let line = "\(ISO8601DateFormatter().string(from: Date())) Reflector: \(message)\n"
            if let data = line.data(using: .utf8),
               let h = FileHandle(forWritingAtPath: "/Users/justinmann/Desktop/rfcomm_connect.log") {
                h.seekToEndOfFile(); h.write(data); h.closeFile()
            }
            Task { @MainActor in
                self?.errorMessage = message
                self?.statusMessage = message
                self?.connectionLog.append(message)
                self?.announceAccessibility(message)
            }
        }
    }

    // MARK: - Audio Engine Setup

    private func setupAudioEngine() {
        audioEngine.onCapturedFrame = { [weak self] pcmSamples in
            guard let self, let streamID = self.txStreamID else { return }

            self.codecQueue.async {
                let ambeData = self.codec.encode(pcm: pcmSamples)

                let frame = DVFrame(
                    streamID: streamID,
                    frameCounter: self.txFrameCounter,
                    ambeData: ambeData,
                    slowData: DExtraProtocol.fillerSlowData
                )
                self.reflectorClient?.sendVoiceFrame(frame)

                self.txFrameCounter = (self.txFrameCounter + 1) % DExtraProtocol.framesPerSuperframe
            }

            Task { @MainActor in
                self.txLevel = self.audioEngine.txLevel
            }
        }
    }

    // MARK: - Heard Stations

    private func addHeardStation(callsign: String) {
        let trimmed = callsign.trimmingCharacters(in: .whitespaces)
        guard !trimmed.isEmpty else { return }

        // New transmission — reset slow data decoder
        slowDataDecoder.reset()
        rxSlowDataText = ""
        rxGPSPosition = ""

        let station = HeardStation(callsign: trimmed, timestamp: Date())
        heardStations.insert(station, at: 0)
        if heardStations.count > maxHeardStations {
            heardStations.removeLast()
        }

        statusMessage = "Hearing \(trimmed)"
        announceAccessibility("\(trimmed) transmitting")
    }

    // MARK: - Accessibility

    func announceAccessibility(_ message: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high
            ]
        )
    }
}
