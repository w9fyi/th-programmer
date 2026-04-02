// CallChannelView.swift — 6 call channels grouped by band

import SwiftUI

struct CallChannelView: View {
    @EnvironmentObject var store: RadioStore
    @State private var editTarget: Int? = nil

    // Channel numbers for each call channel (EXTD_NUMBERS indices 131–136)
    private let vhfChannels:  [Int] = [1131, 1132]   // VHF  Call A, Call D
    private let mhzChannels:  [Int] = [1133, 1134]   // 220M Call A, Call D
    private let uhfChannels:  [Int] = [1135, 1136]   // UHF  Call A, Call D

    var body: some View {
        Group {
            if store.memoryMap == nil {
                noImagePlaceholder
            } else {
                List {
                    callSection(title: "VHF",     channelNumbers: vhfChannels)
                    callSection(title: "220 MHz",  channelNumbers: mhzChannels)
                    callSection(title: "UHF",      channelNumbers: uhfChannels)
                }
                .listStyle(.inset)
                .accessibilityLabel("Call channels, 6 channels")
            }
        }
        .sheet(item: Binding(
            get: { editTarget.map { IdentifiableInt(id: $0) } },
            set: { editTarget = $0?.id }
        )) { target in
            ChannelEditSheet(channelNumber: target.id)
                .environmentObject(store)
        }
    }

    // MARK: - Section builder

    @ViewBuilder
    private func callSection(title: String, channelNumbers: [Int]) -> some View {
        Section(title) {
            ForEach(channelNumbers, id: \.self) { num in
                let ch = store.memoryMap!.channel(number: num)
                CallChannelRow(channel: ch, isModified: store.modifiedChannels.contains(num))
                    .contentShape(Rectangle())
                    .onTapGesture(count: 2) { editTarget = num }
                    .accessibilityHint("Double-tap or press Return to edit")
                    .onKeyPress(.return) {
                        editTarget = num
                        return .handled
                    }
            }
        }
    }

    // MARK: - Empty state

    private var noImagePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "phone.fill")
                .font(.system(size: 48))
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("No memory image loaded")
                .font(.title3)
                .foregroundStyle(.secondary)
            Text("Download from your radio or open a .d74/.d75 file.")
                .font(.callout)
                .foregroundStyle(.tertiary)
                .multilineTextAlignment(.center)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }
}

// MARK: - Row

private struct CallChannelRow: View {
    let channel: ChannelMemory
    let isModified: Bool

    var body: some View {
        HStack(spacing: 10) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(channel.extdNumber ?? "Call")
                        .font(.body.weight(.medium))
                    if isModified {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Modified, not yet uploaded")
                    }
                }
                if !channel.empty {
                    Text(freqLabel)
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.secondary)
                    if !channel.name.isEmpty {
                        Text(channel.name)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                } else {
                    Text("(empty)")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                }
            }

            Spacer()

            if !channel.empty {
                Text(channel.mode.label)
                    .font(.caption2)
                    .padding(.horizontal, 5)
                    .padding(.vertical, 2)
                    .background(Color.accentColor.opacity(0.14))
                    .clipShape(RoundedRectangle(cornerRadius: 4))
                    .accessibilityHidden(true)
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var freqLabel: String {
        let mhz = Double(channel.freq) / 1_000_000.0
        let dup  = channel.duplex == .simplex ? "" : " \(channel.duplex.label)"
        return String(format: "%.4f MHz\(dup)", mhz)
    }

    private var a11yLabel: String {
        let label = channel.extdNumber ?? "Call channel"
        if channel.empty { return "\(label), empty" }
        let freq = String(format: "%.4f megahertz", Double(channel.freq) / 1_000_000.0)
        let name = channel.name.isEmpty ? "" : ", \(channel.name)"
        let mod  = isModified ? ", modified" : ""
        return "\(label)\(name), \(freq), \(channel.mode.label)\(mod)"
    }
}

// MARK: - Helpers

private struct IdentifiableInt: Identifiable { let id: Int }
