// CommunicationSettingsView.swift — Port, Bluetooth, radio ops, file ops, SD card

import SwiftUI
import AppKit

struct CommunicationSettingsView: View {
    @EnvironmentObject var store: RadioStore

    var body: some View {
        ScrollView {
            Form {
                portSection
                bluetoothSection
                operationsSection
                liveControlSection
                fileSection
            }
            .formStyle(.grouped)
        }
        .onAppear { store.bluetooth.refreshPaired() }
        .onChange(of: store.bluetooth.scanStatus) { _, status in
            guard !status.isEmpty else { return }
            store.announceAccessibility(status)
        }
    }

    // MARK: - Port

    private var portSection: some View {
        Section("Serial Port") {
            HStack {
                Picker("Port", selection: $store.portPath) {
                    if store.availablePorts.isEmpty {
                        Text("No ports found").tag("")
                    }
                    ForEach(store.availablePorts, id: \.self) { path in
                        Text(portLabel(path)).tag(path)
                    }
                }
                .accessibilityLabel("Serial port selection")
                .disabled(store.availablePorts.isEmpty)

                Button {
                    store.refreshPorts()
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                        .labelStyle(.iconOnly)
                }
                .accessibilityLabel("Refresh port list")
                .help("Refresh available serial ports")
            }

            if !store.portPath.isEmpty {
                let name = URL(fileURLWithPath: store.portPath).lastPathComponent
                if name.lowercased().contains("th-d75") || name.lowercased().contains("th-d74") {
                    Label("This appears to be a Bluetooth port. Use the USB cable for cloning.", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Warning: Bluetooth port selected. Use USB cable port for downloading and uploading.")
                }
            }
        }
    }

    // MARK: - Bluetooth

    private var bluetoothSection: some View {
        Section("Bluetooth") {
            if store.bluetooth.radios.isEmpty && !store.bluetooth.isScanning {
                Text("No paired TH-D75 found.")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            } else {
                ForEach(store.bluetooth.radios) { radio in
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(radio.name).font(.body)
                            Text(radio.statusLabel)
                                .font(.caption)
                                .foregroundStyle(radio.portPath != nil ? .green : .secondary)
                        }
                        Spacer()
                        if radio.portPath != nil {
                            Button("Select") {
                                store.portPath = radio.portPath!
                                store.refreshPorts()
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Select \(radio.name) as active port")
                        } else {
                            Button("Connect") {
                                Task { await store.connectBluetooth(radio) }
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Connect to \(radio.name) via Bluetooth")
                            .accessibilityHint("Opens Bluetooth connection and waits for virtual serial port")
                        }
                    }
                    .accessibilityElement(children: .combine)
                }
            }

            if store.bluetooth.isScanning {
                HStack(spacing: 6) {
                    ProgressView().controlSize(.small).accessibilityHidden(true)
                    Text(store.bluetooth.scanStatus)
                        .font(.caption).foregroundStyle(.secondary)
                    Spacer()
                    Button("Stop") { store.bluetooth.stopScan() }
                        .buttonStyle(.borderless).font(.caption)
                }
            } else {
                Button {
                    store.bluetooth.startScan()
                } label: {
                    Label("Scan for TH-D75…", systemImage: "antenna.radiowaves.left.and.right")
                }
                .accessibilityLabel("Scan for nearby TH-D75 Bluetooth devices")
                .accessibilityHint("Searches for unpaired TH-D75 radios. Paired devices appear automatically.")

                if !store.bluetooth.scanStatus.isEmpty {
                    Text(store.bluetooth.scanStatus)
                        .font(.caption).foregroundStyle(.secondary)
                }
            }
        }
    }

    // MARK: - Operations

    private var operationsSection: some View {
        Section("Radio Operations") {
            Button {
                Task { await store.downloadFromRadio() }
            } label: {
                Label("Download from Radio", systemImage: "arrow.down.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(store.portPath.isEmpty || store.isBusy)
            .accessibilityLabel("Download memory from radio")
            .accessibilityHint("Reads all channel memories from the TH-D75 via USB or Bluetooth")

            Button {
                Task { await store.diagnoseRadio() }
            } label: {
                Label("Run Protocol Diagnostic", systemImage: "stethoscope")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(store.portPath.isEmpty || store.isBusy)
            .accessibilityLabel("Run protocol diagnostic")
            .accessibilityHint("Tries multiple command formats and logs responses to /tmp/thd75_swift.log")

            Button {
                Task { await store.uploadToRadio() }
            } label: {
                Label("Upload to Radio", systemImage: "arrow.up.circle")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(store.portPath.isEmpty || store.memoryMap == nil || store.isBusy)
            .accessibilityLabel("Upload memory to radio")
            .accessibilityHint("Writes all channel memories to the TH-D75 via USB or Bluetooth")

            if store.isBusy, let p = store.progress {
                ProgressView(value: p.fraction) {
                    Text("\(p.message) — \(Int(p.fraction * 100))%")
                        .font(.caption)
                }
                .accessibilityLabel(p.message)
                .accessibilityValue("\(p.current) of \(p.total) blocks")
            }
        }
    }

    // MARK: - Live Control

    private var liveControlSection: some View {
        Section("Live Control") {
            if store.liveConnected {
                // Frequency display
                if let state = store.liveState {
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(state.frequencyMHz + " MHz")
                                .font(.system(.title2, design: .monospaced))
                                .accessibilityLabel("Frequency: \(state.frequencyMHz) megahertz")
                            HStack(spacing: 8) {
                                Text("VFO \(state.vfo == 0 ? "A" : "B")")
                                    .foregroundStyle(.secondary)
                                Text(state.modeName)
                                    .foregroundStyle(.secondary)
                                if state.busy {
                                    Label("Busy", systemImage: "waveform")
                                        .foregroundStyle(.orange)
                                        .font(.caption)
                                        .accessibilityLabel("Carrier detected")
                                }
                            }
                            .font(.caption)
                        }
                        Spacer()
                        // Step buttons
                        HStack(spacing: 4) {
                            Button {
                                Task { await store.stepLiveFrequency(up: false) }
                            } label: {
                                Image(systemName: "minus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Step frequency down")
                            .help("Step frequency down one tuning step")

                            Button {
                                Task { await store.stepLiveFrequency(up: true) }
                            } label: {
                                Image(systemName: "plus.circle")
                            }
                            .buttonStyle(.borderless)
                            .accessibilityLabel("Step frequency up")
                            .help("Step frequency up one tuning step")
                        }
                        .font(.title2)
                    }
                    .accessibilityElement(children: .contain)

                    // VFO selector
                    Picker("VFO", selection: Binding(
                        get: { state.vfo },
                        set: { v in Task { await store.selectLiveVFO(v) } }
                    )) {
                        Text("VFO A").tag(UInt8(0))
                        Text("VFO B").tag(UInt8(1))
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("VFO selection")

                    // Mode picker
                    Picker("Mode", selection: Binding(
                        get: { state.mode },
                        set: { m in Task { await store.setLiveMode(m) } }
                    )) {
                        ForEach(Array(LiveRadioState.modeNames.enumerated()), id: \.offset) { i, name in
                            Text(name).tag(UInt8(i))
                        }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("Mode selection")
                } else {
                    HStack(spacing: 6) {
                        ProgressView().controlSize(.small).accessibilityHidden(true)
                        Text("Reading radio state…")
                            .font(.caption).foregroundStyle(.secondary)
                    }
                }

                Button("Disconnect Live") {
                    store.disconnectLive()
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Disconnect live radio control")
            } else {
                Button {
                    Task { await store.connectLive() }
                } label: {
                    Label("Connect Live…", systemImage: "dot.radiowaves.left.and.right")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .disabled(store.portPath.isEmpty || store.isBusy)
                .accessibilityLabel("Connect to radio for live control")
                .accessibilityHint("Opens a real-time CAT command session. No clone mode required.")
            }
        }
    }

    // MARK: - File

    private var fileSection: some View {
        Section("File") {
            Button {
                openFilePanel()
            } label: {
                Label("Open .d74 / .d75…", systemImage: "folder")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Open memory file from disk")

            Button {
                saveFilePanel()
            } label: {
                Label("Save .d75…", systemImage: "square.and.arrow.down")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .disabled(store.memoryMap == nil)
            .accessibilityLabel("Save memory file to disk")

            Button {
                importSDCard()
            } label: {
                Label("Import from SD Card…", systemImage: "sdcard")
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .accessibilityLabel("Import memory file from SD card")
            .accessibilityHint("Opens file picker at Volumes, select a .d74 or .d75 file from your SD card")
        }
    }

    // MARK: - Helpers

    private func portLabel(_ path: String) -> String {
        let name = URL(fileURLWithPath: path).lastPathComponent
        if name.contains("usbmodem") { return "\(name)  ← TH-D75 USB (recommended)" }
        if name.lowercased() == "cu.th-d75" || name.lowercased() == "cu.th-d74" {
            return "\(name)  (Bluetooth — not for cloning)"
        }
        return name
    }

    private func openFilePanel() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.message = "Open a TH-D74 or TH-D75 memory file"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            store.loadFile(url: url)
        }
    }

    private func saveFilePanel() {
        let panel = NSSavePanel()
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = "memory.d75"
        panel.message = "Save memory image"
        panel.prompt = "Save"
        if panel.runModal() == .OK, let url = panel.url {
            store.saveFile(url: url)
        }
    }

    private func importSDCard() {
        let panel = NSOpenPanel()
        panel.allowsOtherFileTypes = true
        panel.message = "Select a .d74 or .d75 file from your SD card"
        panel.prompt = "Import"
        panel.directoryURL = URL(fileURLWithPath: "/Volumes")
        if panel.runModal() == .OK, let url = panel.url {
            store.loadFile(url: url)
        }
    }
}
