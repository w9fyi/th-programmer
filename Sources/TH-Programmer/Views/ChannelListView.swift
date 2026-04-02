// ChannelListView.swift — Memory channels 0–999

import SwiftUI

private struct EditTarget: Identifiable {
    let id: Int   // channel number
}

struct ChannelListView: View {
    @EnvironmentObject var store: RadioStore
    @State private var searchText  = ""
    @State private var showEmpty   = false
    @State private var groupFilter: Int? = nil
    @State private var editTarget: EditTarget? = nil

    var body: some View {
        Group {
            if store.memoryMap == nil {
                emptyState
            } else {
                VStack(spacing: 0) {
                    filterBar
                    Divider()
                    channelList
                }
            }
        }
        .searchable(text: $searchText, prompt: "Search by name or frequency")
        .sheet(item: $editTarget) { target in
            ChannelEditSheet(channelNumber: target.id)
                .environmentObject(store)
        }
    }

    // MARK: - Filter bar

    private var filterBar: some View {
        HStack(spacing: 8) {
            Toggle("Show Empty", isOn: $showEmpty)
                .toggleStyle(.checkbox)
                .accessibilityLabel("Show empty channels")

            Spacer()

            if !store.modifiedChannels.isEmpty {
                Label("\(store.modifiedChannels.count) unsaved", systemImage: "pencil.circle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("\(store.modifiedChannels.count) channels modified, not yet uploaded")
            }

            Picker("Group", selection: $groupFilter) {
                Text("All Groups").tag(Optional<Int>.none)
                ForEach(0..<GROUP_COUNT, id: \.self) { i in
                    Text(store.groups.indices.contains(i) ? groupLabel(store.groups[i]) : "Group \(i)")
                        .tag(Optional(i))
                }
            }
            .frame(width: 160)
            .accessibilityLabel("Filter by group")
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 5)
    }

    // MARK: - Empty state

    private var emptyState: some View {
        VStack(spacing: 16) {
            Image(systemName: "radio")
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
            HStack(spacing: 12) {
                Button {
                    Task { await store.downloadFromRadio() }
                } label: {
                    Label("Download from Radio", systemImage: "arrow.down.circle")
                }
                .disabled(store.portPath.isEmpty || store.isBusy)
                .controlSize(.large)
                .accessibilityLabel("Download memory from radio")

                Button {
                    openFilePanel()
                } label: {
                    Label("Open File…", systemImage: "folder")
                }
                .controlSize(.large)
                .accessibilityLabel("Open a .d74 or .d75 memory file")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .padding(40)
    }

    // MARK: - Channel list

    private var channelList: some View {
        List(filteredChannels, id: \.number, selection: $store.selectedNumber) { ch in
            ChannelRow(channel: ch, isModified: store.modifiedChannels.contains(ch.number))
                .tag(ch.number)
                .contentShape(Rectangle())
                .onTapGesture(count: 2) {
                    editTarget = EditTarget(id: ch.number)
                }
                .accessibilityHint("Double-tap or press Return to edit")
        }
        .listStyle(.plain)
        .accessibilityLabel("Memory channels, \(filteredChannels.count) channels")
        .onKeyPress(.return) {
            guard let n = store.selectedNumber else { return .ignored }
            editTarget = EditTarget(id: n)
            return .handled
        }
    }

    // MARK: - Filtering — regular channels only (0–999)

    private var filteredChannels: [ChannelMemory] {
        var all = store.channels   // 0–999 only
        if !showEmpty { all = all.filter { !$0.empty } }
        if let g = groupFilter { all = all.filter { !$0.empty && $0.group == g } }
        if !searchText.isEmpty {
            let q = searchText.lowercased()
            all = all.filter {
                $0.name.lowercased().contains(q) ||
                "\($0.number)".contains(q) ||
                $0.freqMHz.contains(q)
            }
        }
        return all
    }

    private func groupLabel(_ group: ChannelGroup) -> String {
        let name = group.name.trimmingCharacters(in: .whitespaces)
        return name.isEmpty ? "Group \(group.index)" : "\(group.index): \(name)"
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
}

// MARK: - Channel Row

struct ChannelRow: View {
    let channel: ChannelMemory
    let isModified: Bool

    var body: some View {
        HStack(spacing: 10) {
            Text(numberLabel)
                .font(.caption.monospacedDigit())
                .foregroundStyle(.secondary)
                .frame(width: 46, alignment: .trailing)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 4) {
                    Text(displayName)
                        .font(.body)
                        .foregroundStyle(channel.empty ? .tertiary : .primary)
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

            if channel.skip {
                Image(systemName: "s.circle")
                    .font(.caption)
                    .foregroundStyle(.orange)
                    .accessibilityLabel("Scan skip")
            }
        }
        .padding(.vertical, 3)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(accessibilityLabel)
    }

    private var numberLabel: String {
        channel.extdNumber ?? String(format: "%03d", channel.number)
    }

    private var displayName: String {
        if channel.empty { return "(empty)" }
        return channel.name.isEmpty ? "(no name)" : channel.name
    }

    private var freqLabel: String {
        let mhz = Double(channel.freq) / 1_000_000.0
        let dup  = channel.duplex == .simplex ? "" : " \(channel.duplex.label)"
        return String(format: "%.4f MHz\(dup)", mhz)
    }

    private var accessibilityLabel: String {
        if channel.empty { return "Channel \(numberLabel), empty" }
        let name = channel.name.isEmpty ? "no name" : channel.name
        let freq = String(format: "%.4f megahertz", Double(channel.freq) / 1_000_000.0)
        let mod  = isModified ? ", modified" : ""
        let skip = channel.skip ? ", scan skip" : ""
        return "Channel \(numberLabel), \(name), \(freq), \(channel.mode.label)\(mod)\(skip)"
    }
}
