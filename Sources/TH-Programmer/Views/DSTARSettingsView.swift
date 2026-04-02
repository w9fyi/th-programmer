// DSTARSettingsView.swift — D-STAR callsign, repeater, and options settings tab

import SwiftUI
import Combine

struct DSTARSettingsView: View {
    @EnvironmentObject var store: RadioStore
    @State private var settings: DSTARSettings = DSTARSettings(from: Data())
    @State private var original: DSTARSettings = DSTARSettings(from: Data())

    var body: some View {
        VStack(spacing: 0) {
            if store.memoryMap == nil {
                noImagePlaceholder
            } else {
                ScrollView {
                    Form {
                        myStationSection
                        aBandRepeaterSection
                        bBandRepeaterSection
                        dvOptionsSection
                        dvMenuOptionsSection
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
                    store.applyDSTARSettings(settings)
                    original = settings
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.memoryMap == nil || settings == original)
                .accessibilityLabel("Save D-STAR settings to memory image")
            }
            .padding(12)
        }
        .onAppear { loadSettings() }
        .onReceive(store.$memoryMap) { _ in loadSettings() }
    }

    // MARK: - Sections

    private var myStationSection: some View {
        Section("My Station") {
            callField("MY Callsign (8 chars)", text: $settings.myCallsign, maxLen: 8,
                      label: "My D-STAR callsign, up to 8 characters, space-padded")

            callField("Module Suffix (4 chars)", text: $settings.myCallsignSuffix, maxLen: 4,
                      label: "My callsign module suffix, e.g. space-space-space-A for module A")
        }
    }

    private var aBandRepeaterSection: some View {
        Section("A Band Repeater") {
            callField("RPT1 (8 chars)", text: $settings.aBandRPT1, maxLen: 8,
                      label: "A band repeater 1 callsign, gateway or local repeater")
            callField("RPT2 (8 chars)", text: $settings.aBandRPT2, maxLen: 8,
                      label: "A band repeater 2 callsign, used for linking")
        }
    }

    private var bBandRepeaterSection: some View {
        Section("B Band Repeater") {
            callField("RPT1 (8 chars)", text: $settings.bBandRPT1, maxLen: 8,
                      label: "B band repeater 1 callsign")
            callField("RPT2 (8 chars)", text: $settings.bBandRPT2, maxLen: 8,
                      label: "B band repeater 2 callsign")
        }
    }

    private var dvOptionsSection: some View {
        Section("DV Options") {
            pickerRow("Auto Reply", selection: $settings.autoReply,
                      options: DSTARSettings.autoReplyOptions,
                      label: "D-STAR auto reply mode, off, on, or on with voice message")

            Toggle("Direct Reply", isOn: $settings.directReply)
                .accessibilityLabel("D-STAR direct reply, replies without going through a repeater")

            pickerRow("Auto Reply Timing", selection: $settings.autoReplyTiming,
                      options: DSTARSettings.autoReplyTimingOptions,
                      label: "Auto reply timing, delay before sending the automatic reply")

            pickerRow("Data TX End Timing", selection: $settings.dataTxEndTiming,
                      options: DSTARSettings.dataTxEndTimingOptions,
                      label: "Data transmit end timing, delay after last data packet before TX ends")

            Toggle("RX AFC", isOn: $settings.rxAFC)
                .accessibilityLabel("RX automatic frequency control, corrects for slight frequency offset")

            Toggle("FM Auto Detect on DV", isOn: $settings.fmAutoDetOnDV)
                .accessibilityLabel("FM auto detect on DV channel, automatically switches to FM if DV is absent")
            // Break Call (Menu 619) is a transient runtime flag — cleared on power off, not stored in file.
        }
    }

    private var dvMenuOptionsSection: some View {
        Section("Digital Squelch & Data") {
            Stepper("EMR Volume: \(settings.emrVolume)",
                    value: $settings.emrVolume, in: 1...50)
                .accessibilityLabel("EMR emergency volume level \(settings.emrVolume) of 50")
                .accessibilityValue("\(settings.emrVolume)")

            pickerRow("Data Frame Output", selection: $settings.dataFrameOutput,
                      options: DSTARSettings.dataFrameOutputOptions,
                      label: "Data frame output filter, all frames, related to DSQ, or DATA mode only")

            pickerRow("Digital Squelch", selection: $settings.digitalSquelchType,
                      options: DSTARSettings.digitalSquelchOptions,
                      label: "Digital squelch type, off, callsign squelch, or code squelch")

            pickerRow("Digital Code", selection: $settings.digitalCode,
                      options: DSTARSettings.digitalCodeOptions,
                      label: "Digital squelch code number, off or codes 1 through 5")
        }
    }

    // MARK: - Helpers

    @ViewBuilder
    private func pickerRow(_ title: String, selection: Binding<UInt8>,
                           options: [String], label: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, name in
                Text(name).tag(UInt8(index))
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func callField(_ title: String, text: Binding<String>,
                           maxLen: Int, label: String) -> some View {
        LabeledContent(title) {
            TextField(String(repeating: " ", count: maxLen), text: text)
                .font(.system(.body, design: .monospaced))
                .frame(width: CGFloat(maxLen) * 12 + 16)
                .onChange(of: text.wrappedValue) { _, v in
                    if v.count > maxLen { text.wrappedValue = String(v.prefix(maxLen)) }
                }
        }
        .accessibilityLabel(label)
    }

    private var noImagePlaceholder: some View {
        VStack(spacing: 10) {
            Image(systemName: "dot.radiowaves.left.and.right")
                .font(.largeTitle)
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No memory image loaded.")
                .foregroundStyle(.secondary)
            Text("Download from radio or open a file to edit D-STAR settings.")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding()
    }

    private func loadSettings() {
        guard let map = store.memoryMap else { return }
        let s = map.dstarSettings()
        settings = s
        original = s
    }
}
