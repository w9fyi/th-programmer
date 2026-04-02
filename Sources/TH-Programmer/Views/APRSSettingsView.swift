// APRSSettingsView.swift — APRS beacon/symbol/path settings tab

import SwiftUI
import Combine

struct APRSSettingsView: View {
    @EnvironmentObject var store: RadioStore
    @State private var settings: APRSSettings = APRSSettings(from: Data())
    @State private var original: APRSSettings = APRSSettings(from: Data())

    var body: some View {
        VStack(spacing: 0) {
            if store.memoryMap == nil && !store.liveConnected {
                noImagePlaceholder
            } else {
                ScrollView {
                    Form {
                        // Live CAT controls (shown when radio is connected)
                        if store.liveConnected {
                            liveAPRSSection
                        }
                        if store.memoryMap != nil {
                            myStationSection
                            beaconSection
                            if settings.beaconMode == 3 { smartBeaconingSection }
                            pathSection
                            statusSection
                            dataSection
                        }
                    }
                    .formStyle(.grouped)
                    .padding(.bottom, 8)
                }
            }
            Divider()
            HStack {
                Spacer()
                Button("Revert") {
                    settings = original
                }
                .disabled(settings == original || store.memoryMap == nil)
                Button("Save") {
                    store.applyAPRSSettings(settings)
                    original = settings
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.memoryMap == nil || settings == original)
                .accessibilityLabel("Save APRS settings to memory image")
            }
            .padding(12)
        }
        .onAppear { loadSettings() }
        .onReceive(store.$memoryMap) { _ in loadSettings() }
    }

    // MARK: - Live CAT APRS Controls

    private var liveAPRSSection: some View {
        Section("Live Radio Control") {
            LabeledContent("TNC Mode") {
                Picker("TNC Mode", selection: tncModeBinding) {
                    Text("Off").tag(UInt8(0))
                    Text("APRS").tag(UInt8(1))
                }
                .pickerStyle(.segmented)
                .frame(width: 160)
                .accessibilityLabel("TNC mode, \(store.tncMode == 0 ? "off" : "APRS")")
                .accessibilityHint("Enable or disable the APRS TNC on the radio")
            }

            LabeledContent("Beacon Mode") {
                Picker("Beacon Mode", selection: beaconModeBinding) {
                    Text("Manual").tag(UInt8(0))
                    Text("PTT").tag(UInt8(1))
                    Text("Auto").tag(UInt8(2))
                    Text("Smart").tag(UInt8(3))
                }
                .pickerStyle(.segmented)
                .frame(width: 240)
                .accessibilityLabel("Beacon mode, \(beaconModeLabel(store.beaconMode))")
            }

            LabeledContent("Position Source") {
                Picker("Position Source", selection: positionSourceBinding) {
                    Text("GPS").tag(UInt8(0))
                    Text("Stored 1").tag(UInt8(1))
                    Text("Stored 2").tag(UInt8(2))
                    Text("Stored 3").tag(UInt8(3))
                    Text("Stored 4").tag(UInt8(4))
                    Text("Stored 5").tag(UInt8(5))
                }
                .pickerStyle(.menu)
                .frame(width: 130)
                .accessibilityLabel("APRS position source")
            }

            Button("Send Beacon") {
                Task { await store.triggerAPRSBeacon() }
            }
            .buttonStyle(.bordered)
            .accessibilityLabel("Send APRS beacon now")
            .accessibilityHint("Triggers a single APRS position beacon. TNC must be on.")
        }
    }

    private var tncModeBinding: Binding<UInt8> {
        Binding(
            get: { store.tncMode },
            set: { v in Task { await store.setLiveTNCMode(mode: v, band: store.tncBand) } }
        )
    }

    private var beaconModeBinding: Binding<UInt8> {
        Binding(
            get: { store.beaconMode },
            set: { v in Task { await store.setLiveBeaconMode(v) } }
        )
    }

    private var positionSourceBinding: Binding<UInt8> {
        Binding(
            get: { store.positionSource },
            set: { v in Task { await store.setLivePositionSource(v) } }
        )
    }

    private func beaconModeLabel(_ mode: UInt8) -> String {
        switch mode {
        case 0: return "Manual"
        case 1: return "PTT"
        case 2: return "Auto"
        case 3: return "SmartBeaconing"
        default: return "Unknown"
        }
    }

    // MARK: - Sections

    private var myStationSection: some View {
        Section("My Station") {
            LabeledContent("Callsign") {
                TextField("e.g. AI5OS", text: $settings.myCallsign)
                    .frame(width: 120)
                    .onChange(of: settings.myCallsign) { _, v in
                        if v.count > 9 { settings.myCallsign = String(v.prefix(9)) }
                    }
            }
            .accessibilityLabel("My APRS callsign, up to 9 characters")

            Picker("SSID", selection: $settings.mySSID) {
                ForEach(Array(APRSSettings.ssidOptions.enumerated()), id: \.offset) { i, label in
                    Text(label).tag(UInt8(i))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("APRS SSID, identifies this station among your callsign group")

            Picker("Position Comment", selection: $settings.positionComment) {
                ForEach(Array(APRSSettings.positionCommentOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Position comment, describes your current status in APRS beacons")

            symbolPicker
        }
    }

    private var beaconSection: some View {
        Section("Beacon") {
            Picker("Mode", selection: $settings.beaconMode) {
                ForEach(Array(APRSSettings.beaconModeOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Beacon transmission mode")

            if settings.beaconMode == 1 || settings.beaconMode == 2 {
                Picker("Interval", selection: $settings.beaconInterval) {
                    ForEach(Array(APRSSettings.beaconIntervalOptions.enumerated()), id: \.offset) { i, label in
                        Text(label).tag(UInt8(i))
                    }
                }
                .pickerStyle(.menu)
                .accessibilityLabel("Beacon transmission interval")
            }

            Toggle("Decay Algorithm", isOn: $settings.decayAlgorithm)
                .accessibilityLabel("Beacon decay algorithm, doubles interval after each transmission until max")

            Toggle("Proportional Pathing", isOn: $settings.propPathing)
                .accessibilityLabel("Proportional pathing, alternates beacon path length to reduce network load")

            Toggle("Include Speed", isOn: $settings.beaconIncludeSpeed)
                .accessibilityLabel("Include speed in beacon packet")

            Toggle("Include Altitude", isOn: $settings.beaconIncludeAlt)
                .accessibilityLabel("Include altitude in beacon packet")
        }
    }

    private var smartBeaconingSection: some View {
        Section("SmartBeaconing") {
            Stepper("Low Speed: \(settings.smartBeaconingLow) mph",
                    value: $settings.smartBeaconingLow, in: 1...30)
                .accessibilityLabel("SmartBeaconing low speed threshold, \(settings.smartBeaconingLow) mph. Below this speed, slow rate is used.")

            Stepper("High Speed: \(settings.smartBeaconingHigh) mph",
                    value: $settings.smartBeaconingHigh, in: 10...100)
                .accessibilityLabel("SmartBeaconing high speed threshold, \(settings.smartBeaconingHigh) mph. Above this speed, fast rate is used.")

            Stepper("Slow Rate: \(settings.smartBeaconingSlowRate) min",
                    value: $settings.smartBeaconingSlowRate, in: 1...100)
                .accessibilityLabel("Slow beacon rate at low speed, \(settings.smartBeaconingSlowRate) minutes between beacons")

            Stepper("Fast Rate: \(settings.smartBeaconingFastRate) sec",
                    value: $settings.smartBeaconingFastRate, in: 10...180)
                .accessibilityLabel("Fast beacon rate at high speed, \(settings.smartBeaconingFastRate) seconds between beacons")

            Stepper("Turn Angle: \(settings.smartBeaconingTurnAngle)°",
                    value: $settings.smartBeaconingTurnAngle, in: 5...90)
                .accessibilityLabel("Turn angle threshold, \(settings.smartBeaconingTurnAngle) degrees change triggers an extra beacon")

            Stepper("Turn Slope: \(settings.smartBeaconingTurnSlope)",
                    value: $settings.smartBeaconingTurnSlope, in: 1...255)
                .accessibilityLabel("Turn slope factor, \(settings.smartBeaconingTurnSlope), controls angle sensitivity at speed")

            Stepper("Turn Time: \(settings.smartBeaconingTurnTime) sec",
                    value: $settings.smartBeaconingTurnTime, in: 5...180)
                .accessibilityLabel("Minimum time between turn-triggered beacons, \(settings.smartBeaconingTurnTime) seconds")
        }
    }

    private var pathSection: some View {
        Section("Path") {
            Picker("Digipeater Path", selection: $settings.pathType) {
                ForEach(Array(APRSSettings.pathTypeOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("APRS digipeater path for beacon forwarding")

            if settings.pathType == 0 {
                Toggle("WIDE1-1", isOn: $settings.pathWide1_1)
                    .accessibilityLabel("Include WIDE1-1 in New-N path, enables digi fill-in")

                Stepper("Total Hops: \(settings.pathTotalHops)",
                        value: $settings.pathTotalHops, in: 0...7)
                    .accessibilityLabel("Total path hops, \(settings.pathTotalHops)")
            }
        }
    }

    private var statusSection: some View {
        Section("Status Texts") {
            statusTextField(1, text: $settings.statusText1, rate: $settings.statusTxRate1)
            statusTextField(2, text: $settings.statusText2, rate: $settings.statusTxRate2)
            statusTextField(3, text: $settings.statusText3, rate: $settings.statusTxRate3)
            statusTextField(4, text: $settings.statusText4, rate: $settings.statusTxRate4)
            statusTextField(5, text: $settings.statusText5, rate: $settings.statusTxRate5)

            Picker("Active Status", selection: $settings.statusTextMessageSelected) {
                ForEach(0..<5) { i in
                    Text("Status \(i + 1)").tag(UInt8(i))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Which status text is transmitted in beacons")
        }
    }

    private var dataSection: some View {
        Section("Data") {
            Picker("Data Band", selection: $settings.dataBand) {
                ForEach(Array(APRSSettings.dataBandOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Data band for APRS packet I/O, A band or B band")

            Picker("Data Speed", selection: $settings.dataSpeed) {
                ForEach(Array(APRSSettings.dataSpeedOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Data speed for APRS packets, 1200 or 9600 baud")

            Picker("TX Delay", selection: $settings.txDelay) {
                ForEach(Array(APRSSettings.txDelayOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Transmit delay before packet data, allows repeater to key up")

            Picker("DCD Sense", selection: $settings.dcdSense) {
                ForEach(Array(APRSSettings.dcdSenseOptions.enumerated()), id: \.offset) { i, name in
                    Text(name).tag(UInt8(i))
                }
            }
            .pickerStyle(.menu)
            .accessibilityLabel("Data carrier detect sense mode, controls when the radio transmits")
        }
    }

    // MARK: - Reusable builders

    @ViewBuilder
    private func statusTextField(_ n: Int, text: Binding<String>, rate: Binding<UInt8>) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            TextField("Status \(n) (up to 45 chars)", text: text)
                .onChange(of: text.wrappedValue) { _, v in
                    if v.count > 45 { text.wrappedValue = String(v.prefix(45)) }
                }
                .accessibilityLabel("APRS status message \(n), up to 45 characters")
            Picker("TX Rate \(n)", selection: rate) {
                ForEach(Array(APRSSettings.statusTxRateOptions.enumerated()), id: \.offset) { i, label in
                    Text(label).tag(UInt8(i))
                }
            }
            .pickerStyle(.segmented)
            .accessibilityLabel("Status text \(n) transmit rate")
        }
        .padding(.vertical, 2)
    }

    private var symbolPicker: some View {
        HStack {
            Picker("Symbol Table", selection: $settings.symbolTable) {
                Text("Primary (/)").tag(UInt8(0))
                Text("Alternate (\\)").tag(UInt8(1))
            }
            .pickerStyle(.menu)
            .accessibilityLabel("APRS symbol table, primary slash or alternate backslash")
            .frame(width: 160)

            Stepper("Code: \(String(UnicodeScalar(settings.symbolCode)))",
                    value: $settings.symbolCode, in: 33...126)
                .accessibilityLabel("APRS symbol code character, \(String(UnicodeScalar(settings.symbolCode)))")
        }
    }

    private var noImagePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "location.circle")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No memory image loaded.")
                .foregroundStyle(.secondary)
            Text("Download from radio or open a file to edit APRS settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    // MARK: - Helpers

    private func loadSettings() {
        guard let map = store.memoryMap else { return }
        let s = map.aprsSettings()
        settings = s
        original = s
    }
}
