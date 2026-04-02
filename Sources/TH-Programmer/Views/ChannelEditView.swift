// ChannelEditView.swift — Form for editing a single channel memory

import SwiftUI
import AppKit

struct ChannelEditView: View {
    @Binding var channel: ChannelMemory

    // Local freq text field state
    @State private var freqText: String = ""
    @State private var offsetText: String = ""
    @FocusState private var freqFocused: Bool
    @FocusState private var offsetFocused: Bool
    @State private var showClearConfirm = false

    var body: some View {
        Form {
            if channel.empty {
                emptyChannelSection
            } else {
                basicSection
                toneSection
                if channel.mode.isDigital {
                    dvSection
                }
                advancedSection
            }
        }
        .formStyle(.grouped)
        .navigationTitle(channelTitle)
        .onAppear { syncFromChannel() }
        .onChange(of: channel.number) { _, _ in syncFromChannel() }
        .onChange(of: channel.toneMode) { _, mode in
            switch mode {
            case .none:  announceToVoiceOver("Tone squelch off")
            case .tone:  announceToVoiceOver("Transmit CTCSS tone picker available")
            case .tsql:  announceToVoiceOver("Receive CTCSS tone picker available")
            case .dtcs:  announceToVoiceOver("DTCS code picker available")
            case .cross: announceToVoiceOver("Cross tone pickers available")
            }
        }
        .onChange(of: channel.duplex) { _, duplex in
            if duplex == .simplex {
                announceToVoiceOver("Simplex, offset field removed")
            } else {
                announceToVoiceOver("Offset field available")
            }
        }
        .confirmationDialog(
            "Clear channel \(channel.number)?",
            isPresented: $showClearConfirm,
            titleVisibility: .visible
        ) {
            Button("Clear", role: .destructive) {
                channel.empty = true
                announceToVoiceOver("Channel \(channel.number) cleared")
            }
            Button("Cancel", role: .cancel) {}
        } message: {
            Text("All data in this channel will be erased.")
        }
    }

    // MARK: - Sections

    private var emptyChannelSection: some View {
        Section {
            Text("This channel is empty.")
                .foregroundStyle(.secondary)
            Button("Create Channel") {
                channel.empty = false
                channel.name = ""
                channel.freq = 146_000_000
                channel.offset = 600_000
                channel.mode = .fm
                channel.duplex = .simplex
                syncFromChannel()
            }
            .accessibilityLabel("Create channel \(channel.number)")
        } header: {
            Text("Channel \(channel.number)")
        }
    }

    private var basicSection: some View {
        Section("Basic") {
            // Name
            if !channel.immutable.contains("name") {
                LabeledContent("Name") {
                    TextField("Up to 16 characters", text: $channel.name)
                        .onChange(of: channel.name) { _, newValue in channel.name = String(newValue.prefix(NAME_LENGTH)) }
                        .accessibilityLabel("Channel name, up to 16 characters")
                }
            }

            // Frequency
            LabeledContent("Frequency (MHz)") {
                TextField("e.g. 146.520", text: $freqText)
                    .focused($freqFocused)
                    .onSubmit { commitFreq() }
                    .onChange(of: freqFocused) { _, focused in if !focused { commitFreq() } }
                    .accessibilityLabel("Frequency in megahertz")
            }

            // Mode
            if !channel.immutable.contains("mode") {
                Picker("Mode", selection: $channel.mode) {
                    ForEach(RadioMode.allCases) { mode in
                        Text(mode.label).tag(mode)
                    }
                }
                .accessibilityLabel("Modulation mode")
            }

            // Duplex
            Picker("Duplex", selection: $channel.duplex) {
                ForEach(DuplexMode.allCases) { d in
                    Text(d.label.isEmpty ? "Simplex" : d.label).tag(d)
                }
            }
            .accessibilityLabel("Duplex direction")

            // Offset
            if channel.duplex != .simplex {
                LabeledContent("Offset (kHz)") {
                    TextField("e.g. 600", text: $offsetText)
                        .focused($offsetFocused)
                        .onSubmit { commitOffset() }
                        .onChange(of: offsetFocused) { _, focused in if !focused { commitOffset() } }
                        .accessibilityLabel("Offset in kilohertz")
                }
            }

            // Tuning step
            Picker("Tuning Step", selection: $channel.tuningStep) {
                ForEach(TUNE_STEPS, id: \.self) { step in
                    Text(stepLabel(step)).tag(step)
                }
            }
            .accessibilityLabel("Tuning step")

            // Narrow
            Toggle("Narrow", isOn: $channel.narrow)
                .accessibilityLabel("Narrow bandwidth")
        }
    }

    private var toneSection: some View {
        Section("Tone / Squelch") {
            // Tone mode
            Picker("Tone Mode", selection: $channel.toneMode) {
                ForEach(ToneMode.allCases) { m in
                    Text(m.label).tag(m)
                }
            }
            .accessibilityLabel("Tone mode")

            if channel.toneMode == .tone || channel.toneMode == .cross {
                Picker("Transmit Tone (CTCSS)", selection: $channel.rtone) {
                    ForEach(CTCSS_TONES, id: \.self) { t in
                        Text(toneLabel(t)).tag(t)
                    }
                }
                .accessibilityLabel("Transmit CTCSS tone")
            }

            if channel.toneMode == .tsql || channel.toneMode == .cross {
                Picker("Receive Tone (CTCSS)", selection: $channel.ctone) {
                    ForEach(CTCSS_TONES, id: \.self) { t in
                        Text(toneLabel(t)).tag(t)
                    }
                }
                .accessibilityLabel("Receive CTCSS tone")
            }

            if channel.toneMode == .dtcs || channel.toneMode == .cross {
                Picker("DTCS Code", selection: $channel.dtcs) {
                    ForEach(DTCS_CODES, id: \.self) { c in
                        Text(String(format: "%03d", c)).tag(c)
                    }
                }
                .accessibilityLabel("DTCS code")
            }

            if channel.toneMode == .cross {
                Picker("Cross Mode", selection: $channel.crossMode) {
                    ForEach(CrossMode.allCases) { m in
                        Text(m.label).tag(m)
                    }
                }
                .accessibilityLabel("Cross tone mode")
            }
        }
    }

    private var dvSection: some View {
        Section("D-STAR") {
            LabeledContent("UR Call") {
                TextField("CQCQCQ  ", text: $channel.dvURCall)
                    .onChange(of: channel.dvURCall) { _, newValue in channel.dvURCall = String(newValue.prefix(8)) }
                    .accessibilityLabel("D-STAR UR call, up to 8 characters")
            }
            LabeledContent("RPT1 Call") {
                TextField("        ", text: $channel.dvRPT1Call)
                    .onChange(of: channel.dvRPT1Call) { _, newValue in channel.dvRPT1Call = String(newValue.prefix(8)) }
                    .accessibilityLabel("D-STAR repeater 1 call, up to 8 characters")
            }
            LabeledContent("RPT2 Call") {
                TextField("        ", text: $channel.dvRPT2Call)
                    .onChange(of: channel.dvRPT2Call) { _, newValue in channel.dvRPT2Call = String(newValue.prefix(8)) }
                    .accessibilityLabel("D-STAR repeater 2 call, up to 8 characters")
            }
            Picker("Digital Squelch", selection: $channel.digSquelch) {
                Text("None").tag(0)
                Text("Code").tag(1)
                Text("Callsign").tag(2)
            }
            .accessibilityLabel("Digital squelch mode")
        }
    }

    private var advancedSection: some View {
        Section("Advanced") {
            Toggle("Skip (lockout)", isOn: $channel.skip)
                .accessibilityLabel("Skip channel during scan")

            Picker("Group", selection: $channel.group) {
                ForEach(0..<GROUP_COUNT, id: \.self) { i in
                    Text("Group \(i)").tag(i)
                }
            }
            .accessibilityLabel("Channel group")

            Button("Clear Channel", role: .destructive) {
                showClearConfirm = true
            }
            .accessibilityLabel("Clear channel \(channel.number), removing all data")
        }
    }

    // MARK: - Helpers

    private var channelTitle: String {
        let num = channel.extdNumber ?? String(format: "Channel %03d", channel.number)
        if channel.empty { return "\(num) (empty)" }
        let name = channel.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? num : "\(num) — \(name)"
    }

    private func syncFromChannel() {
        let mhz = Double(channel.freq) / 1_000_000.0
        freqText = String(format: "%.6g", mhz)
        let khz = Double(channel.offset) / 1_000.0
        offsetText = String(format: "%.4g", khz)
    }

    private func commitFreq() {
        if let mhz = Double(freqText), mhz > 0 {
            channel.freq = UInt32(mhz * 1_000_000.0)
            announceToVoiceOver("Frequency set to \(freqText) megahertz")
        } else {
            // Restore to current value on invalid input
            let mhz = Double(channel.freq) / 1_000_000.0
            freqText = String(format: "%.6g", mhz)
            announceToVoiceOver("Invalid frequency. Restored to \(freqText) megahertz")
        }
    }

    private func commitOffset() {
        if let khz = Double(offsetText), khz >= 0 {
            channel.offset = UInt32(khz * 1_000.0)
            announceToVoiceOver("Offset set to \(offsetText) kilohertz")
        } else {
            let khz = Double(channel.offset) / 1_000.0
            offsetText = String(format: "%.4g", khz)
            announceToVoiceOver("Invalid offset. Restored to \(offsetText) kilohertz")
        }
    }

    private func stepLabel(_ step: Double) -> String {
        step == Double(Int(step)) ? "\(Int(step)) kHz" : "\(step) kHz"
    }

    private func toneLabel(_ hz: Double) -> String {
        String(format: "%.1f Hz", hz)
    }

    private func announceToVoiceOver(_ message: String) {
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
