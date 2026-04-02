// WeatherChannelView.swift — WX1–WX10 weather channels (channels 1101–1110)
// Frequencies are preset NOAA values programmed by the radio firmware.
// Only channel names are user-editable.

import SwiftUI

struct WeatherChannelView: View {
    @EnvironmentObject var store: RadioStore
    @State private var editTarget: Int? = nil

    // Channel numbers for WX1–WX10 (EXTD_NUMBERS indices 101–110)
    private let wxChannelNumbers: [Int] = Array(1101...1110)

    var body: some View {
        Group {
            if store.memoryMap == nil {
                noImagePlaceholder
            } else {
                VStack(spacing: 0) {
                    infoBar
                    Divider()
                    List {
                        ForEach(wxChannelNumbers, id: \.self) { num in
                            let ch = store.memoryMap!.channel(number: num)
                            WeatherChannelRow(
                                channel: ch,
                                isModified: store.modifiedChannels.contains(num)
                            )
                            .contentShape(Rectangle())
                            .onTapGesture(count: 2) { editTarget = num }
                            .accessibilityHint("Double-tap or press Return to edit name")
                        }
                    }
                    .listStyle(.inset)
                    .accessibilityLabel("Weather channels, 10 channels")
                }
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

    // MARK: - Info bar

    private var infoBar: some View {
        HStack(spacing: 6) {
            Image(systemName: "info.circle")
                .foregroundStyle(.secondary)
                .accessibilityHidden(true)
            Text("Frequencies are preset NOAA values. Only channel names can be changed.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityLabel("Weather channel frequencies are preset NOAA values. Only channel names are user-editable.")
    }

    // MARK: - Empty state

    private var noImagePlaceholder: some View {
        VStack(spacing: 12) {
            Image(systemName: "cloud.rain.fill")
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

private struct WeatherChannelRow: View {
    let channel: ChannelMemory
    let isModified: Bool

    var body: some View {
        HStack(spacing: 10) {
            // Channel label (WX1–WX10)
            Text(channel.extdNumber ?? "WX")
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 36, alignment: .trailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(channel.name.isEmpty ? "(no name)" : channel.name)
                        .font(.body)
                        .foregroundStyle(channel.name.isEmpty ? .tertiary : .primary)
                    if isModified {
                        Image(systemName: "pencil.circle.fill")
                            .font(.caption)
                            .foregroundStyle(.orange)
                            .accessibilityLabel("Modified, not yet uploaded")
                    }
                }
                Text(freqLabel)
                    .font(.caption.monospacedDigit())
                    .foregroundStyle(.secondary)
            }

            Spacer()

            // Read-only badge
            Text("Preset")
                .font(.caption2)
                .padding(.horizontal, 5)
                .padding(.vertical, 2)
                .background(Color.gray.opacity(0.14))
                .clipShape(RoundedRectangle(cornerRadius: 4))
                .accessibilityHidden(true)
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(a11yLabel)
    }

    private var freqLabel: String {
        String(format: "%.3f MHz", Double(channel.freq) / 1_000_000.0)
    }

    private var a11yLabel: String {
        let label = channel.extdNumber ?? "Weather channel"
        let name  = channel.name.isEmpty ? "no name" : channel.name
        let freq  = String(format: "%.3f megahertz", Double(channel.freq) / 1_000_000.0)
        let mod   = isModified ? ", name modified" : ""
        return "\(label), \(name), \(freq), preset frequency\(mod)"
    }
}

// MARK: - Helpers

private struct IdentifiableInt: Identifiable { let id: Int }
