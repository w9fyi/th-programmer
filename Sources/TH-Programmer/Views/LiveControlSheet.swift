// LiveControlSheet.swift — Real-time VFO control sheet

import SwiftUI

struct LiveControlSheet: View {
    @EnvironmentObject var store: RadioStore
    @Environment(\.dismiss) private var dismiss

    // Local editable frequency string (MHz, e.g. "146.520000")
    @State private var freqField = ""
    @State private var isEditingFreq = false

    // Callsign editing
    @State private var callsignField = ""
    @State private var isEditingCallsign = false

    // D-STAR reflector terminal
    @State private var reflectorType: ReflectorTarget.ReflectorType = .ref
    @State private var reflectorNumber: String = "001"
    @State private var reflectorModule: Character = "A"

    var body: some View {
        VStack(spacing: 0) {
            // MARK: Header
            HStack {
                Text("Live Control")
                    .font(.headline)
                Spacer()
                if let state = store.liveState, state.busy {
                    Label("Busy", systemImage: "waveform")
                        .font(.caption)
                        .foregroundStyle(.orange)
                        .accessibilityLabel("Carrier detected on this frequency")
                }
            }
            .padding([.horizontal, .top], 20)
            .padding(.bottom, 12)

            Divider()

            ScrollView {
                VStack(spacing: 20) {

                    // MARK: Frequency display
                    frequencyDisplay

                    // MARK: S-Meter
                    sMeterDisplay

                    // MARK: Frequency entry
                    frequencyEntry

                    // MARK: Step buttons
                    stepButtons

                    Divider()

                    // MARK: VFO + Mode
                    vfoAndMode

                    Divider()

                    // MARK: Live Settings
                    liveSettingsSection

                    // MARK: Radio Info (shown once fetched)
                    if store.radioInfo != nil {
                        Divider()
                        radioInfoSection
                    }

                    Divider()

                    // MARK: TX Power
                    txPowerSection

                    Divider()

                    // MARK: APRS Beacon
                    aprsBeaconSection

                    // MARK: D-STAR Reflector (only in DV/DR mode)
                    if let state = store.liveState, state.mode == 1 || state.mode == 7 {
                        Divider()
                        reflectorTerminalSection
                    }
                }
                .padding(20)
            }

            Divider()

            // MARK: Bottom bar
            HStack {
                Button("Disconnect") {
                    store.disconnectLive()
                    dismiss()
                }
                .foregroundStyle(.red)
                .accessibilityLabel("Disconnect live radio control and close this panel")

                Spacer()

                Button("Done") { dismiss() }
                    .buttonStyle(.borderedProminent)
                    .keyboardShortcut(.return, modifiers: [])
                    .accessibilityLabel("Close live control panel")
            }
            .padding(16)
        }
        .frame(minWidth: 360, idealWidth: 420, maxWidth: 480, minHeight: 520)
        .onAppear {
            syncFreqField()
            syncCallsignField()
        }
        .onChange(of: store.liveState) { _, _ in
            if !isEditingFreq { syncFreqField() }
        }
        .onChange(of: store.radioInfo) { _, _ in
            if !isEditingCallsign { syncCallsignField() }
        }
    }

    // MARK: - VFO subviews

    private var frequencyDisplay: some View {
        VStack(spacing: 4) {
            let state = store.liveState
            Text((state?.frequencyMHz ?? "---") + " MHz")
                .font(.system(size: 36, weight: .light, design: .monospaced))
                .accessibilityLabel("Current frequency: \((state?.frequencyMHz ?? "unknown")) megahertz")

            HStack(spacing: 12) {
                Text("VFO \(state?.vfo == 0 ? "A" : "B")")
                    .foregroundStyle(.secondary)
                Text(state?.modeName ?? "—")
                    .foregroundStyle(.secondary)
            }
            .font(.callout)
            .accessibilityElement(children: .combine)
            .accessibilityLabel("VFO \(store.liveState?.vfo == 0 ? "A" : "B"), mode \(store.liveState?.modeName ?? "unknown")")
        }
        .frame(maxWidth: .infinity)
    }

    private var frequencyEntry: some View {
        HStack(spacing: 8) {
            TextField("MHz", text: $freqField, onEditingChanged: { editing in
                isEditingFreq = editing
            })
            .font(.system(.body, design: .monospaced))
            .multilineTextAlignment(.trailing)
            .frame(width: 140)
            .textFieldStyle(.roundedBorder)
            .onSubmit { tuneToField() }
            .accessibilityLabel("Frequency entry in megahertz")
            .accessibilityHint("Type a frequency in megahertz and press Tune or Return to set it")

            Text("MHz")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Button("Tune") { tuneToField() }
                .buttonStyle(.bordered)
                .disabled(!isValidFreq)
                .accessibilityLabel("Tune to entered frequency")
        }
        .frame(maxWidth: .infinity, alignment: .center)
    }

    private var stepButtons: some View {
        HStack(spacing: 16) {
            Button {
                Task { await store.stepLiveFrequency(up: false) }
            } label: {
                Label("Step Down", systemImage: "chevron.down.circle.fill")
                    .font(.title2)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Step frequency down one tuning step")
            .help("Step frequency down")

            Text("Step")
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)

            Button {
                Task { await store.stepLiveFrequency(up: true) }
            } label: {
                Label("Step Up", systemImage: "chevron.up.circle.fill")
                    .font(.title2)
                    .labelStyle(.iconOnly)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Step frequency up one tuning step")
            .help("Step frequency up")
        }
        .frame(maxWidth: .infinity)
    }

    private var vfoAndMode: some View {
        VStack(spacing: 16) {
            LabeledContent("VFO") {
                Picker("VFO", selection: vfoBinding) {
                    Text("A").tag(UInt8(0))
                    Text("B").tag(UInt8(1))
                }
                .pickerStyle(.segmented)
                .frame(width: 120)
                .accessibilityLabel("VFO selection, A or B")
            }

            LabeledContent("Mode") {
                Picker("Mode", selection: modeBinding) {
                    ForEach(Array(LiveRadioState.modeNames.enumerated()), id: \.offset) { i, name in
                        Text(name).tag(UInt8(i))
                    }
                }
                .pickerStyle(.menu)
                .frame(width: 120)
                .accessibilityLabel("Mode selection")
            }

            LabeledContent("VFO/MR") {
                Picker("VFO/Memory", selection: vfoMemModeBinding) {
                    Text("VFO").tag(UInt8(0))
                    Text("Memory").tag(UInt8(1))
                    Text("Call").tag(UInt8(2))
                }
                .pickerStyle(.segmented)
                .frame(width: 200)
                .accessibilityLabel("VFO memory mode, \(vfoMemModeLabel(store.vfoMemModeA))")
            }

            LabeledContent("Tuning Step") {
                Picker("Tuning Step", selection: tuningStepBinding) {
                    Text("5 kHz").tag(UInt8(0))
                    Text("6.25 kHz").tag(UInt8(1))
                    Text("8.33 kHz").tag(UInt8(2))
                    Text("9 kHz").tag(UInt8(3))
                    Text("10 kHz").tag(UInt8(4))
                    Text("12.5 kHz").tag(UInt8(5))
                    Text("15 kHz").tag(UInt8(6))
                    Text("20 kHz").tag(UInt8(7))
                    Text("25 kHz").tag(UInt8(8))
                    Text("30 kHz").tag(UInt8(9))
                    Text("50 kHz").tag(UInt8(10))
                    Text("100 kHz").tag(UInt8(11))
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .accessibilityLabel("Tuning step size")
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - Live Settings section

    private var liveSettingsSection: some View {
        GroupBox("Radio Settings") {
            VStack(spacing: 12) {
                LabeledContent("AF Gain") {
                    Stepper("\(store.afGain)", value: afGainBinding, in: 0...200)
                        .frame(width: 130)
                        .accessibilityLabel("AF gain, \(store.afGain)")
                        .accessibilityHint("Adjust audio output volume, 0 to 200")
                }

                LabeledContent("Backlight") {
                    Picker("Backlight", selection: backlightBinding) {
                        Text("Manual").tag(UInt8(0))
                        Text("On").tag(UInt8(1))
                        Text("Auto").tag(UInt8(2))
                        Text("Auto DC").tag(UInt8(3))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    .accessibilityLabel("Backlight mode")
                }

                LabeledContent("Bar Antenna") {
                    Picker("Bar Antenna", selection: barAntennaBinding) {
                        Text("External").tag(UInt8(0))
                        Text("Internal").tag(UInt8(1))
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 160)
                    .accessibilityLabel("Antenna, \(store.barAntenna == 0 ? "external" : "internal")")
                }

                LabeledContent("Power Save") {
                    Text(store.powerSave == 0 ? "Off" : "On")
                        .foregroundStyle(.secondary)
                        .accessibilityLabel("Power save \(store.powerSave == 0 ? "off" : "on"), read-only")
                }

                LabeledContent("Dual Band") {
                    Toggle("", isOn: dualBandBinding)
                        .labelsHidden()
                        .accessibilityLabel("Dual band \(store.dualBand ? "on" : "off")")
                        .accessibilityHint("Toggle between dual and single band display")
                }

                Divider()

                LabeledContent("VOX") {
                    Toggle("", isOn: voxBinding)
                        .labelsHidden()
                        .accessibilityLabel("VOX \(store.voxOn ? "on" : "off")")
                }

                LabeledContent("VOX Gain") {
                    Stepper("\(store.voxGain)", value: voxGainBinding, in: 0...9)
                        .frame(width: 130)
                        .accessibilityLabel("VOX gain, \(store.voxGain)")
                }

                LabeledContent("VOX Delay") {
                    Picker("VOX Delay", selection: voxDelayBinding) {
                        Text("250 ms").tag(UInt8(0))
                        Text("500 ms").tag(UInt8(1))
                        Text("750 ms").tag(UInt8(2))
                        Text("1000 ms").tag(UInt8(3))
                        Text("1500 ms").tag(UInt8(4))
                        Text("2000 ms").tag(UInt8(5))
                        Text("3000 ms").tag(UInt8(6))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 130)
                    .accessibilityLabel("VOX delay")
                }

                Divider()

                LabeledContent("Attenuator A") {
                    Toggle("", isOn: attenuatorABinding)
                        .labelsHidden()
                        .accessibilityLabel("Band A attenuator \(store.attenuatorA ? "on" : "off")")
                }

                LabeledContent("Attenuator B") {
                    Toggle("", isOn: attenuatorBBinding)
                        .labelsHidden()
                        .accessibilityLabel("Band B attenuator \(store.attenuatorB ? "on" : "off")")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Radio Info section

    private var radioInfoSection: some View {
        GroupBox("Radio Info") {
            VStack(alignment: .leading, spacing: 10) {

                // Callsign (editable)
                LabeledContent("Callsign") {
                    HStack(spacing: 6) {
                        TextField("Callsign", text: $callsignField, onEditingChanged: { editing in
                            isEditingCallsign = editing
                        })
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 90)
                        .textFieldStyle(.roundedBorder)
                        .onSubmit { Task { await store.setLiveCallsign(callsignField) } }
                        .accessibilityLabel("D-STAR callsign")
                        .accessibilityHint("Press Return or Set to send to radio")

                        if isEditingCallsign {
                            Button("Set") { Task { await store.setLiveCallsign(callsignField) } }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .accessibilityLabel("Set callsign")
                        }
                    }
                }

                if let info = store.radioInfo {
                    if !info.firmwareVersion.isEmpty {
                        LabeledContent("Firmware", value: info.firmwareVersion)
                    }

                    if !info.serialNumber.isEmpty {
                        LabeledContent("Serial", value: "\(info.serialNumber) (\(info.modelVariant))")
                    }

                    if !info.clockString.isEmpty {
                        let formatted = THD75LiveConnection.formatClockString(info.clockString)
                                        ?? info.clockString
                        LabeledContent("Clock (UTC)", value: formatted)
                            .accessibilityLabel("GPS clock: \(formatted) UTC")
                    }

                    LabeledContent("GPS") {
                        HStack(spacing: 6) {
                            Circle()
                                .fill(info.gpsFixed ? Color.green : Color.orange)
                                .frame(width: 8, height: 8)
                                .accessibilityHidden(true)
                            Text(info.gpsFixed ? "Fixed" : (info.gpsEnabled ? "Searching…" : "Off"))
                                .foregroundStyle(info.gpsFixed ? .primary : .secondary)
                        }
                    }
                    .accessibilityLabel("GPS: \(info.gpsFixed ? "fixed" : (info.gpsEnabled ? "searching" : "off"))")

                    if let pos = info.position {
                        LabeledContent("Position") {
                            Text(pos.coordinateString)
                                .font(.system(.body, design: .monospaced))
                                .textSelection(.enabled)
                        }
                        .accessibilityLabel("Position: \(pos.coordinateString)")

                        if let speed = pos.speedString {
                            LabeledContent("Speed", value: speed)
                                .accessibilityLabel("Speed: \(speed)")
                        }
                    }
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - TX Power section

    private var txPowerSection: some View {
        GroupBox("TX Power") {
            VStack(spacing: 12) {
                LabeledContent("Band A") {
                    Picker("Band A TX Power", selection: txPowerABinding) {
                        Text("High").tag(UInt8(0))
                        Text("Medium").tag(UInt8(1))
                        Text("Low").tag(UInt8(2))
                        Text("EL").tag(UInt8(3))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .accessibilityLabel("Band A transmit power, \(txPowerLabel(store.txPowerA))")
                    .accessibilityHint("Choose transmit power level for band A")
                }

                LabeledContent("Band B") {
                    Picker("Band B TX Power", selection: txPowerBBinding) {
                        Text("High").tag(UInt8(0))
                        Text("Medium").tag(UInt8(1))
                        Text("Low").tag(UInt8(2))
                        Text("EL").tag(UInt8(3))
                    }
                    .pickerStyle(.menu)
                    .frame(width: 120)
                    .accessibilityLabel("Band B transmit power, \(txPowerLabel(store.txPowerB))")
                    .accessibilityHint("Choose transmit power level for band B")
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private func txPowerLabel(_ level: UInt8) -> String {
        switch level {
        case 0: return "High"
        case 1: return "Medium"
        case 2: return "Low"
        case 3: return "EL"
        default: return "Unknown"
        }
    }

    // MARK: - APRS Beacon section

    private var aprsBeaconSection: some View {
        GroupBox("APRS") {
            Button("Send Beacon") {
                Task { await store.triggerAPRSBeacon() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Send APRS beacon")
            .accessibilityHint("Triggers a single APRS position beacon. TNC must be on.")
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - D-STAR Reflector Terminal section

    private var reflectorTerminalSection: some View {
        GroupBox("D-STAR Reflector") {
            VStack(spacing: 12) {
                LabeledContent("Type") {
                    Picker("Reflector type", selection: $reflectorType) {
                        ForEach(ReflectorTarget.ReflectorType.allCases) { t in
                            Text(t.rawValue).tag(t)
                        }
                    }
                    .pickerStyle(.segmented)
                    .frame(width: 200)
                    .accessibilityLabel("Reflector type, \(reflectorType.rawValue)")
                }

                LabeledContent("Number") {
                    TextField("001", text: $reflectorNumber)
                        .font(.system(.body, design: .monospaced))
                        .frame(width: 60)
                        .textFieldStyle(.roundedBorder)
                        .onChange(of: reflectorNumber) { _, v in
                            if v.count > 3 { reflectorNumber = String(v.prefix(3)) }
                        }
                        .accessibilityLabel("Reflector number")
                        .accessibilityHint("Enter a 1 to 3 digit reflector number, for example 001")
                }

                LabeledContent("Module") {
                    Picker("Module", selection: $reflectorModule) {
                        ForEach(Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ"), id: \.self) { ch in
                            Text(String(ch)).tag(ch)
                        }
                    }
                    .pickerStyle(.menu)
                    .frame(width: 80)
                    .accessibilityLabel("Reflector module, \(String(reflectorModule))")
                }

                HStack(spacing: 12) {
                    Button("Connect") {
                        guard let num = Int(reflectorNumber) else { return }
                        let target = ReflectorTarget(type: reflectorType, number: num, module: reflectorModule)
                        Task { await store.connectReflector(target) }
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(!isValidReflectorNumber)
                    .accessibilityLabel("Connect to \(reflectorType.rawValue) \(reflectorNumber) module \(String(reflectorModule))")
                    .accessibilityHint("Links your radio to this D-STAR reflector")

                    Button("Disconnect") {
                        Task { await store.disconnectReflector() }
                    }
                    .buttonStyle(.bordered)
                    .foregroundStyle(.red)
                    .accessibilityLabel("Disconnect from reflector")
                    .accessibilityHint("Unlinks your radio from the current D-STAR reflector")

                    Button("Info") {
                        Task { await store.queryReflectorInfo() }
                    }
                    .buttonStyle(.bordered)
                    .accessibilityLabel("Query reflector info")
                    .accessibilityHint("Requests information from the connected reflector. Listen for the audio response.")
                }

                if !store.reflectorStatus.isEmpty {
                    Text(store.reflectorStatus)
                        .font(.callout)
                        .foregroundStyle(.secondary)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .accessibilityLabel("Reflector status: \(store.reflectorStatus)")
                        .accessibilityAddTraits(.updatesFrequently)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var isValidReflectorNumber: Bool {
        guard let num = Int(reflectorNumber) else { return false }
        return num >= 1 && num <= 999
    }

    // MARK: - S-Meter display

    private var sMeterDisplay: some View {
        HStack(spacing: 16) {
            VStack(spacing: 2) {
                Text("A")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("S\(store.sMeterA)")
                    .font(.system(.body, design: .monospaced))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Band A signal, S \(store.sMeterA)")
            .accessibilityAddTraits(.updatesFrequently)

            VStack(spacing: 2) {
                Text("B")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                Text("S\(store.sMeterB)")
                    .font(.system(.body, design: .monospaced))
            }
            .accessibilityElement(children: .combine)
            .accessibilityLabel("Band B signal, S \(store.sMeterB)")
            .accessibilityAddTraits(.updatesFrequently)
        }
        .frame(maxWidth: .infinity)
    }

    // MARK: - Bindings

    private var vfoBinding: Binding<UInt8> {
        Binding(
            get: { store.liveState?.vfo ?? 0 },
            set: { v in Task { await store.selectLiveVFO(v) } }
        )
    }

    private var modeBinding: Binding<UInt8> {
        Binding(
            get: { store.liveState?.mode ?? 0 },
            set: { m in Task { await store.setLiveMode(m) } }
        )
    }

    private var afGainBinding: Binding<Int> {
        Binding(
            get: { Int(store.afGain) },
            set: { v in Task { await store.setLiveAFGain(UInt8(v)) } }
        )
    }

    private var backlightBinding: Binding<UInt8> {
        Binding(
            get: { store.backlight },
            set: { v in Task { await store.setLiveBacklight(v) } }
        )
    }

    private var barAntennaBinding: Binding<UInt8> {
        Binding(
            get: { store.barAntenna },
            set: { v in Task { await store.setLiveBarAntenna(v) } }
        )
    }

    private var voxBinding: Binding<Bool> {
        Binding(
            get: { store.voxOn },
            set: { v in Task { await store.setLiveVOX(v) } }
        )
    }

    private var voxGainBinding: Binding<Int> {
        Binding(
            get: { Int(store.voxGain) },
            set: { v in Task { await store.setLiveVOXGain(UInt8(v)) } }
        )
    }

    private var voxDelayBinding: Binding<UInt8> {
        Binding(
            get: { store.voxDelay },
            set: { v in Task { await store.setLiveVOXDelay(v) } }
        )
    }

    private var dualBandBinding: Binding<Bool> {
        Binding(
            get: { store.dualBand },
            set: { v in Task { await store.setLiveDualBand(v) } }
        )
    }

    private var attenuatorABinding: Binding<Bool> {
        Binding(
            get: { store.attenuatorA },
            set: { v in Task { await store.setLiveAttenuator(band: 0, on: v) } }
        )
    }

    private var attenuatorBBinding: Binding<Bool> {
        Binding(
            get: { store.attenuatorB },
            set: { v in Task { await store.setLiveAttenuator(band: 1, on: v) } }
        )
    }

    private var txPowerABinding: Binding<UInt8> {
        Binding(
            get: { store.txPowerA },
            set: { v in Task { await store.setLiveTxPower(band: 0, level: v) } }
        )
    }

    private var txPowerBBinding: Binding<UInt8> {
        Binding(
            get: { store.txPowerB },
            set: { v in Task { await store.setLiveTxPower(band: 1, level: v) } }
        )
    }

    private var vfoMemModeBinding: Binding<UInt8> {
        Binding(
            get: { store.vfoMemModeA },
            set: { v in Task { await store.setLiveVFOMemMode(band: 0, mode: v) } }
        )
    }

    private var tuningStepBinding: Binding<UInt8> {
        Binding(
            get: { store.tuningStepA },
            set: { v in Task { await store.setLiveTuningStep(band: 0, step: v) } }
        )
    }

    // MARK: - Helpers

    private var isValidFreq: Bool {
        guard let mhz = Double(freqField) else { return false }
        return mhz >= 0.1 && mhz <= 999.9999
    }

    private func tuneToField() {
        guard let mhz = Double(freqField), mhz >= 0.1 && mhz <= 999.9999 else { return }
        let hz = Int(mhz * 1_000_000)
        Task { await store.setLiveFrequency(hz) }
    }

    private func syncFreqField() {
        guard let state = store.liveState else { return }
        freqField = String(format: "%.6f", Double(state.frequencyHz) / 1_000_000.0)
    }

    private func syncCallsignField() {
        guard let info = store.radioInfo, !info.callsign.isEmpty else { return }
        callsignField = info.callsign
    }

    private func vfoMemModeLabel(_ mode: UInt8) -> String {
        switch mode {
        case 0: return "VFO"
        case 1: return "Memory"
        case 2: return "Call"
        case 3: return "DV"
        default: return "Unknown"
        }
    }
}
