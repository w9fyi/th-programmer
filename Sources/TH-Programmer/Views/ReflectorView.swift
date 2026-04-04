// ReflectorView.swift — D-STAR reflector gateway tab

import SwiftUI
import CoreAudio

struct ReflectorView: View {
    @EnvironmentObject var reflectorStore: ReflectorStore
    @EnvironmentObject var reflectorDirectory: ReflectorDirectory

    @State private var reflectorType: ReflectorTarget.ReflectorType = .ref
    @State private var reflectorNumber: String = "001"
    @State private var reflectorModule: String = "A"
    @State private var favoriteLabel: String = ""
    @State private var showAddFavorite: Bool = false

    private let modules = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { String($0) }

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                modeSection
                Divider()
                if reflectorStore.gatewayMode == .mmdvmTerminal {
                    serialPortSection
                    Divider()
                }
                if !reflectorStore.favoritesManager.favorites.isEmpty {
                    favoritesSection
                    Divider()
                }
                connectionSection
                Divider()
                if reflectorStore.gatewayMode == .software {
                    audioSection
                    Divider()
                }
                pttSection
                Divider()
                slowDataSection
                Divider()
                heardStationsSection
            }
            .padding()
        }
        .sheet(isPresented: $reflectorStore.showDirectory) {
            ReflectorDirectorySheet(directory: reflectorDirectory)
                .environmentObject(reflectorStore)
        }
        .sheet(isPresented: $reflectorStore.showAddFavoriteFromMenu) {
            VStack(spacing: 12) {
                Text("Add to Favorites")
                    .font(.headline)
                TextField("Label (e.g., Texas D-STAR)", text: $favoriteLabel)
                    .textFieldStyle(.roundedBorder)
                    .frame(width: 200)
                    .accessibilityLabel("Favorite label")
                HStack {
                    Button("Cancel") {
                        reflectorStore.showAddFavoriteFromMenu = false
                        favoriteLabel = ""
                    }
                    Button("Save") {
                        let label = favoriteLabel.isEmpty
                            ? reflectorStore.connectedReflector.map { "\($0.type.rawValue)\(String(format: "%03d", $0.number)) \($0.module)" } ?? "Favorite"
                            : favoriteLabel
                        reflectorStore.addFavorite(label: label)
                        reflectorStore.showAddFavoriteFromMenu = false
                        favoriteLabel = ""
                    }
                    .buttonStyle(.borderedProminent)
                }
            }
            .padding()
        }
    }

    // MARK: - Mode Section

    private var modeSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                Picker("Gateway Mode", selection: $reflectorStore.gatewayMode) {
                    ForEach(GatewayMode.allCases) { mode in
                        Text(mode.rawValue).tag(mode)
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Gateway mode")
                .accessibilityHint("Software Codec uses Mac audio. MMDVM Terminal uses the TH-D75 radio.")
                .disabled(reflectorStore.connectionState != .disconnected)

                Text(reflectorStore.gatewayMode.description)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } label: {
            Label("Mode", systemImage: "switch.2")
                .font(.headline)
        }
    }

    // MARK: - Serial Port Section (MMDVM mode)

    private var serialPortSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Bluetooth connection for radio
                bluetoothConnectSection

                Divider()

                // Serial port picker
                LabeledContent("Serial Port") {
                    Picker("Serial Port", selection: serialPortBinding) {
                        Text("None").tag("")
                        ForEach(reflectorStore.availableSerialPorts) { port in
                            Text(port.displayName).tag(port.path)
                        }
                    }
                    .frame(minWidth: 200)
                    .accessibilityLabel("Serial port")
                    .accessibilityHint("Select a serial port for USB MMDVM connection. Not needed when using direct Bluetooth RFCOMM.")
                    .disabled(reflectorStore.mmdvmState != .idle)
                }

                HStack(spacing: 12) {
                    Button("Refresh Ports") {
                        reflectorStore.refreshSerialPorts()
                    }
                    .accessibilityLabel("Refresh serial ports")
                    .accessibilityHint("Scan for available serial ports")

                    Button("Connect MMDVM") {
                        reflectorStore.connectMMDVM()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(reflectorStore.selectedSerialPort == nil && reflectorStore.selectedBluetoothRadio == nil && reflectorStore.bluetoothManager.radios.isEmpty || reflectorStore.mmdvmState != .idle)
                    .accessibilityLabel("Connect MMDVM")
                    .accessibilityHint("Connect to the TH-D75 in terminal mode via direct Bluetooth RFCOMM. Radio must be paired and Menu 650 set to Reflector TERM Mode.")

                    Button("Disconnect MMDVM") {
                        reflectorStore.disconnectMMDVM()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(reflectorStore.mmdvmState == .idle)
                    .accessibilityLabel("Disconnect MMDVM")
                }

                // MMDVM Status
                HStack(spacing: 8) {
                    Circle()
                        .fill(mmdvmStatusColor)
                        .frame(width: 10, height: 10)
                        .accessibilityHidden(true)
                    Text(mmdvmStatusText)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                }
                .accessibilityElement(children: .combine)
                .accessibilityLabel("MMDVM status: \(mmdvmStatusText)")
                .accessibilityAddTraits(.updatesFrequently)

                // Terminal mode checklist
                if reflectorStore.mmdvmState == .idle || reflectorStore.mmdvmState == .probing {
                    Text("Before connecting: Set Menu 650 to ON on your TH-D75. Band A should display TERM.")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Important: Set Menu 650 to ON on your TH-D75 before connecting. Band A should display TERM.")
                }
            }
        } label: {
            Label("MMDVM Connection", systemImage: "cable.connector")
                .font(.headline)
        }
        .onAppear {
            reflectorStore.refreshSerialPorts()
            reflectorStore.bluetoothManager.refreshPaired()
        }
    }

    // MARK: - Bluetooth Connect Section

    private var bluetoothConnectSection: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("Bluetooth Radio Connection")
                .font(.subheadline.bold())
                .accessibilityAddTraits(.isHeader)

            if reflectorStore.bluetoothManager.radios.isEmpty {
                Text("No paired TH-D75 found. Pair your radio in macOS System Settings \u{2192} Bluetooth first, then return here to connect.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(reflectorStore.bluetoothManager.radios) { radio in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(radio.name)
                                .font(.callout)
                            Text(radio.statusLabel)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        if radio.portPath != nil {
                            Text("Ready")
                                .font(.caption.bold())
                                .foregroundStyle(.green)
                        } else if radio.isConnected {
                            ProgressView()
                                .controlSize(.small)
                                .accessibilityLabel("Waiting for serial port")
                        } else {
                            Button("Connect") {
                                reflectorStore.connectBluetooth(radio)
                            }
                            .buttonStyle(.bordered)
                            .accessibilityLabel("Connect to \(radio.name) via Bluetooth")
                            .accessibilityHint("Connects to \(radio.name) via Bluetooth for direct RFCOMM gateway mode")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if !reflectorStore.bluetoothManager.connectStatus.isEmpty {
                Text(reflectorStore.bluetoothManager.connectStatus)
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Bluetooth status: \(reflectorStore.bluetoothManager.connectStatus)")
                    .accessibilityAddTraits(.updatesFrequently)
            }

            HStack(spacing: 12) {
                Button("Refresh Paired") {
                    reflectorStore.bluetoothManager.refreshPaired()
                }
                .accessibilityLabel("Refresh paired devices")
                .accessibilityHint("Re-checks macOS paired Bluetooth devices for TH-D74 and TH-D75 radios")

                Button("Scan for Radios") {
                    reflectorStore.scanBluetooth()
                }
                .disabled(reflectorStore.bluetoothManager.isScanning)
                .accessibilityLabel(reflectorStore.bluetoothManager.isScanning ? "Scanning for radios" : "Scan for radios")
                .accessibilityHint("Scan for nearby unpaired TH-D74 and TH-D75 radios via Bluetooth")

                if reflectorStore.bluetoothManager.isScanning {
                    ProgressView()
                        .controlSize(.small)
                    Text(reflectorStore.bluetoothManager.scanStatus)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Favorites Section

    private var favoritesSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(reflectorStore.favoritesManager.favorites) { favorite in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(favorite.label)
                                .font(.callout.bold())
                            Text(favorite.reflectorName)
                                .font(.caption.monospaced())
                                .foregroundStyle(.secondary)
                        }

                        Spacer()

                        Button("Connect") {
                            reflectorStore.connectToFavorite(favorite)
                        }
                        .buttonStyle(.bordered)
                        .disabled(reflectorStore.connectionState != .disconnected)
                        .accessibilityLabel("Connect to \(favorite.label)")
                        .accessibilityHint("Links to \(favorite.reflectorName)")

                        Button("Remove") {
                            reflectorStore.removeFavorite(id: favorite.id)
                        }
                        .buttonStyle(.borderless)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Remove \(favorite.label) from favorites")
                    }
                    .accessibilityElement(children: .combine)
                }
            }
        } label: {
            Label("Favorites", systemImage: "star.fill")
                .font(.headline)
        }
    }

    // MARK: - Connection Section

    private var connectionSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Callsign
                LabeledContent("My Callsign") {
                    TextField("Callsign", text: $reflectorStore.myCallsign)
                        .textFieldStyle(.roundedBorder)
                        .frame(width: 120)
                        .font(.body.monospaced())
                        .textCase(.uppercase)
                        .accessibilityLabel("My callsign")
                        .accessibilityHint("Enter your amateur radio callsign for D-STAR registration")
                        .disabled(reflectorStore.connectionState != .disconnected)
                }

                // Reflector type picker
                LabeledContent("Reflector Type") {
                    Picker("Reflector Type", selection: $reflectorType) {
                        ForEach(ReflectorTarget.ReflectorType.allCases) { type in
                            Text(type.rawValue).tag(type)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 240)
                    .accessibilityLabel("Reflector type")
                    .disabled(reflectorStore.connectionState != .disconnected)
                }

                HStack(spacing: 16) {
                    // Reflector number
                    LabeledContent("Number") {
                        TextField("001", text: $reflectorNumber)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 60)
                            .font(.body.monospaced())
                            .accessibilityLabel("Reflector number")
                            .accessibilityHint("Enter a 1 to 3 digit reflector number")
                            .disabled(reflectorStore.connectionState != .disconnected)
                    }

                    // Module picker
                    LabeledContent("Module") {
                        Picker("Module", selection: $reflectorModule) {
                            ForEach(modules, id: \.self) { mod in
                                Text(mod).tag(mod)
                            }
                        }
                        .frame(width: 60)
                        .accessibilityLabel("Reflector module")
                        .accessibilityHint("Select the module letter A through Z")
                        .disabled(reflectorStore.connectionState != .disconnected)
                    }
                }

                // Connect / Disconnect buttons
                HStack(spacing: 12) {
                    Button("Browse Reflectors…") {
                        reflectorStore.showDirectory = true
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Browse reflector directory")
                    .accessibilityHint("Opens a searchable list of D-STAR reflectors")

                    Button("Connect") {
                        connectToReflector()
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(reflectorStore.connectionState != .disconnected)
                    .accessibilityLabel("Connect to reflector")
                    .accessibilityHint("Links to \(reflectorType.rawValue) \(reflectorNumber) module \(reflectorModule)")

                    Button("Disconnect") {
                        reflectorStore.disconnect()
                    }
                    .buttonStyle(.bordered)
                    .tint(.red)
                    .disabled(reflectorStore.connectionState == .disconnected)
                    .accessibilityLabel("Disconnect from reflector")

                    if reflectorStore.connectionState == .connected {
                        Button("Add to Favorites") {
                            showAddFavorite = true
                        }
                        .buttonStyle(.bordered)
                        .accessibilityLabel("Add current reflector to favorites")
                        .popover(isPresented: $showAddFavorite) {
                            VStack(spacing: 12) {
                                Text("Add to Favorites")
                                    .font(.headline)
                                TextField("Label (e.g., Texas D-STAR)", text: $favoriteLabel)
                                    .textFieldStyle(.roundedBorder)
                                    .frame(width: 200)
                                    .accessibilityLabel("Favorite label")
                                    .accessibilityHint("Enter a name for this favorite")
                                HStack {
                                    Button("Cancel") {
                                        showAddFavorite = false
                                        favoriteLabel = ""
                                    }
                                    Button("Save") {
                                        let label = favoriteLabel.isEmpty
                                            ? reflectorStore.connectedReflector.map { "\($0.type.rawValue)\(String(format: "%03d", $0.number)) \($0.module)" } ?? "Favorite"
                                            : favoriteLabel
                                        reflectorStore.addFavorite(label: label)
                                        showAddFavorite = false
                                        favoriteLabel = ""
                                    }
                                    .buttonStyle(.borderedProminent)
                                }
                            }
                            .padding()
                        }
                    }
                }

                // Status
                Text(reflectorStore.statusMessage)
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Connection status: \(reflectorStore.statusMessage)")
                    .accessibilityAddTraits(.updatesFrequently)

                // Connection log (diagnostic)
                if !reflectorStore.connectionLog.isEmpty {
                    DisclosureGroup("Connection Log") {
                        VStack(alignment: .leading, spacing: 4) {
                            ForEach(Array(reflectorStore.connectionLog.enumerated()), id: \.offset) { _, entry in
                                Text(entry)
                                    .font(.system(.caption, design: .monospaced))
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("Connection log: \(reflectorStore.connectionLog.joined(separator: ". "))")
                    }
                }
            }
        } label: {
            Label("Connection", systemImage: "antenna.radiowaves.left.and.right")
                .font(.headline)
        }
    }

    // MARK: - Audio Section (Software mode only)

    private var audioSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 12) {
                // Input device picker (microphone for TX)
                LabeledContent("Microphone") {
                    Picker("Microphone", selection: inputDeviceBinding) {
                        Text("System Default").tag(AudioDeviceID(0))
                        ForEach(reflectorStore.availableInputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .frame(minWidth: 240)
                    .accessibilityLabel("Microphone")
                    .accessibilityHint("Select the microphone for transmitting. Bluetooth headsets and USB mics appear here once paired in System Settings.")
                }

                // Output device picker (speaker for RX)
                LabeledContent("Speaker") {
                    Picker("Speaker", selection: outputDeviceBinding) {
                        Text("System Default").tag(AudioDeviceID(0))
                        ForEach(reflectorStore.availableOutputDevices) { device in
                            Text(device.name).tag(device.id)
                        }
                    }
                    .frame(minWidth: 240)
                    .accessibilityLabel("Speaker")
                    .accessibilityHint("Select the speaker or headphones for receiving audio. Bluetooth headphones appear here once paired in System Settings.")
                }

                // Bluetooth / external device guidance
                Text("Bluetooth headphones, USB headsets, and other audio devices appear in the pickers above once paired through macOS System Settings \u{2192} Bluetooth.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("Bluetooth headphones, USB headsets, and other audio devices appear in the pickers above once paired through macOS System Settings, Bluetooth.")

                // RX Level
                LabeledContent("RX Level") {
                    ProgressView(value: Double(reflectorStore.rxLevel))
                        .frame(width: 200)
                        .accessibilityLabel("Receive audio level")
                        .accessibilityValue("\(Int(reflectorStore.rxLevel * 100)) percent")
                }

                // TX Level
                LabeledContent("TX Level") {
                    ProgressView(value: Double(reflectorStore.txLevel))
                        .frame(width: 200)
                        .accessibilityLabel("Transmit audio level")
                        .accessibilityValue("\(Int(reflectorStore.txLevel * 100)) percent")
                }
            }
        } label: {
            Label("Audio", systemImage: "speaker.wave.2")
                .font(.headline)
        }
    }

    // MARK: - PTT Section

    private var pttSection: some View {
        GroupBox {
            VStack(spacing: 12) {
                if reflectorStore.gatewayMode == .mmdvmTerminal {
                    Text("PTT is controlled by the radio in terminal mode.")
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .accessibilityLabel("PTT is controlled by the radio in terminal mode")
                } else {
                    Button(action: {
                        reflectorStore.togglePTT()
                    }) {
                        Text(reflectorStore.isPTT ? "Release PTT" : "Push to Talk")
                            .font(.title2.bold())
                            .frame(maxWidth: .infinity)
                            .padding(.vertical, 12)
                    }
                    .buttonStyle(.borderedProminent)
                    .tint(reflectorStore.isPTT ? .red : .accentColor)
                    .disabled(reflectorStore.connectionState != .connected)
                    .accessibilityLabel(reflectorStore.isPTT ? "Release push to talk" : "Push to talk")
                    .accessibilityHint(reflectorStore.isPTT
                        ? "Press to stop transmitting"
                        : "Press to start transmitting. You can also press the space bar.")
                    .keyboardShortcut(.space, modifiers: [])

                    if reflectorStore.isPTT, reflectorStore.txTimeRemaining > 0 {
                        let minutes = reflectorStore.txTimeRemaining / 60
                        let seconds = reflectorStore.txTimeRemaining % 60
                        Text("Time remaining: \(String(format: "%d:%02d", minutes, seconds))")
                            .font(.callout.monospaced())
                            .foregroundStyle(reflectorStore.txTimeRemaining <= 30 ? .red : .secondary)
                            .accessibilityLabel("Transmit time remaining")
                            .accessibilityValue("\(reflectorStore.txTimeRemaining) seconds")
                            .accessibilityAddTraits(.updatesFrequently)
                    }

                    Text("Press Space bar to toggle PTT")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        } label: {
            Label("Transmit", systemImage: "mic.fill")
                .font(.headline)
        }
    }

    // MARK: - Slow Data Section

    private var slowDataSection: some View {
        GroupBox {
            VStack(alignment: .leading, spacing: 8) {
                if reflectorStore.rxSlowDataText.isEmpty && reflectorStore.rxGPSPosition.isEmpty {
                    Text("No slow data received")
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .center)
                        .padding(.vertical, 8)
                        .accessibilityLabel("No slow data received")
                } else {
                    if !reflectorStore.rxSlowDataText.isEmpty {
                        LabeledContent("Message") {
                            Text(reflectorStore.rxSlowDataText)
                                .font(.body.monospaced())
                        }
                        .accessibilityLabel("Slow data message: \(reflectorStore.rxSlowDataText)")
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                    if !reflectorStore.rxGPSPosition.isEmpty {
                        LabeledContent("GPS") {
                            Text(reflectorStore.rxGPSPosition)
                                .font(.body.monospaced())
                        }
                        .accessibilityLabel("GPS position: \(reflectorStore.rxGPSPosition)")
                        .accessibilityAddTraits(.updatesFrequently)
                    }
                }
            }
        } label: {
            Label("Slow Data", systemImage: "text.bubble")
                .font(.headline)
        }
    }

    // MARK: - Heard Stations Section

    private var heardStationsSection: some View {
        GroupBox {
            if reflectorStore.heardStations.isEmpty {
                Text("No stations heard yet")
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, alignment: .center)
                    .padding(.vertical, 20)
                    .accessibilityLabel("No stations heard yet")
            } else {
                VStack(alignment: .leading, spacing: 4) {
                    // Header row
                    HStack {
                        Text("Callsign")
                            .font(.caption.bold())
                            .frame(width: 100, alignment: .leading)
                        Text("Time")
                            .font(.caption.bold())
                            .frame(width: 80, alignment: .leading)
                        Text("Message")
                            .font(.caption.bold())
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                    .accessibilityHidden(true)

                    Divider()

                    ForEach(reflectorStore.heardStations) { station in
                        HStack {
                            Text(station.callsign)
                                .font(.body.monospaced())
                                .frame(width: 100, alignment: .leading)
                            Text(station.timeString)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(width: 80, alignment: .leading)
                            Text(station.message)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .accessibilityElement(children: .combine)
                        .accessibilityLabel("\(station.callsign) at \(station.timeString)")
                    }
                }
            }
        } label: {
            Label("Heard Stations (\(reflectorStore.heardStations.count))", systemImage: "person.2.wave.2")
                .font(.headline)
        }
    }

    // MARK: - Helpers

    private func connectToReflector() {
        guard let number = Int(reflectorNumber), number >= 1, number <= 999 else {
            reflectorStore.errorMessage = "Reflector number must be 1–999"
            return
        }
        guard let module = reflectorModule.first else { return }

        let target = ReflectorTarget(type: reflectorType, number: number, module: module)
        reflectorStore.connect(to: target)
    }

    private var inputDeviceBinding: Binding<AudioDeviceID> {
        Binding<AudioDeviceID>(
            get: { self.reflectorStore.selectedInputDeviceID ?? 0 },
            set: { self.reflectorStore.setInputDevice($0) }
        )
    }

    private var outputDeviceBinding: Binding<AudioDeviceID> {
        Binding<AudioDeviceID>(
            get: { self.reflectorStore.selectedOutputDeviceID ?? 0 },
            set: { self.reflectorStore.setOutputDevice($0) }
        )
    }

    private var serialPortBinding: Binding<String> {
        Binding<String>(
            get: { self.reflectorStore.selectedSerialPort?.path ?? "" },
            set: { newPath in
                self.reflectorStore.selectedSerialPort = self.reflectorStore.availableSerialPorts.first { $0.path == newPath }
            }
        )
    }

    private var mmdvmStatusColor: Color {
        switch reflectorStore.mmdvmState {
        case .idle: return .gray
        case .probing: return .yellow
        case .ready: return .green
        case .bridging: return .blue
        case .reconnecting: return .orange
        case .error: return .red
        }
    }

    private var mmdvmStatusText: String {
        let transport = reflectorStore.isDirectRFCOMM ? "Direct RFCOMM" : "Serial Port"
        switch reflectorStore.mmdvmState {
        case .idle: return "Not connected"
        case .probing: return "Probing… (\(transport))"
        case .ready:
            if let version = reflectorStore.mmdvmFirmwareVersion {
                return "Ready — \(version) (\(transport))"
            }
            return "Ready (\(transport))"
        case .bridging: return "Bridging active (\(transport))"
        case .reconnecting(let attempt): return "Reconnecting (\(attempt)/10)…"
        case .error(let msg): return "Error: \(msg)"
        }
    }
}
