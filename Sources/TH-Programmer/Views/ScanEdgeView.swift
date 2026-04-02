// ScanEdgeView.swift — 50 scan edge pairs (Lower00–Lower49 / Upper00–Upper49)
// Each pair defines a frequency range for Program Scan.

import SwiftUI

struct ScanEdgeView: View {
    @EnvironmentObject var store: RadioStore
    @State private var editTarget: Int? = nil   // individual channel number being edited

    var body: some View {
        Group {
            if store.memoryMap == nil {
                noImagePlaceholder
            } else {
                List {
                    ForEach(0..<50, id: \.self) { pairIndex in
                        let lowerNum = 1000 + pairIndex * 2
                        let upperNum = 1001 + pairIndex * 2
                        let lower = store.memoryMap!.channel(number: lowerNum)
                        let upper = store.memoryMap!.channel(number: upperNum)
                        ScanEdgePairRow(
                            pairIndex: pairIndex,
                            lower: lower,
                            upper: upper,
                            isModified: store.modifiedChannels.contains(lowerNum)
                                     || store.modifiedChannels.contains(upperNum),
                            onEditLower: { editTarget = lowerNum },
                            onEditUpper: { editTarget = upperNum }
                        )
                    }
                }
                .listStyle(.inset)
                .accessibilityLabel("Scan edge pairs, 50 pairs")
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

    // MARK: - Empty state

    private var noImagePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "waveform.path.ecg")
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

// MARK: - Pair row

private struct ScanEdgePairRow: View {
    let pairIndex: Int
    let lower: ChannelMemory
    let upper: ChannelMemory
    let isModified: Bool
    let onEditLower: () -> Void
    let onEditUpper: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            // Pair label
            Text(String(format: "%02d", pairIndex))
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 24, alignment: .trailing)
                .accessibilityHidden(true)

            // Lower frequency
            edgeCell(channel: lower, label: "Lower", onEdit: onEditLower)

            Image(systemName: "arrow.right")
                .font(.caption)
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)

            // Upper frequency
            edgeCell(channel: upper, label: "Upper", onEdit: onEditUpper)

            if isModified {
                Image(systemName: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Modified, not yet uploaded")
            }
        }
        .padding(.vertical, 4)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    @ViewBuilder
    private func edgeCell(channel: ChannelMemory, label: String, onEdit: @escaping () -> Void) -> some View {
        Button(action: onEdit) {
            VStack(alignment: .leading, spacing: 1) {
                Text(label)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if channel.empty {
                    Text("—")
                        .font(.caption.monospacedDigit())
                        .foregroundStyle(.tertiary)
                } else {
                    Text(freqLabel(channel))
                        .font(.caption.monospacedDigit())
                }
            }
        }
        .buttonStyle(.borderless)
        .frame(minWidth: 90, alignment: .leading)
        .accessibilityLabel("\(label): \(channel.empty ? "empty" : freqLabel(channel))")
        .accessibilityHint("Activate to edit")
    }

    private func freqLabel(_ ch: ChannelMemory) -> String {
        String(format: "%.4f MHz", Double(ch.freq) / 1_000_000.0)
    }

    private var a11yLabel: String {
        let l = lower.empty ? "empty" : String(format: "%.4f megahertz", Double(lower.freq) / 1_000_000.0)
        let u = upper.empty ? "empty" : String(format: "%.4f megahertz", Double(upper.freq) / 1_000_000.0)
        let mod = isModified ? ", modified" : ""
        return "Scan edge pair \(pairIndex), lower \(l), upper \(u)\(mod)"
    }
}

// MARK: - Helpers

private struct IdentifiableInt: Identifiable { let id: Int }
