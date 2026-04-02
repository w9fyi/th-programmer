// RepeaterBookView.swift — Search and import repeaters from RepeaterBook

import SwiftUI

struct RepeaterBookView: View {
    @EnvironmentObject var store: RadioStore
    @Environment(\.dismiss) private var dismiss

    @State private var selectedState = "Texas"
    @State private var county = ""
    @State private var selectedBand = ""
    @State private var results: [RepeaterEntry] = []
    @State private var selections: [String: Bool] = [:]
    @State private var isSearching = false
    @State private var errorMessage: String? = nil

    private let bandOptions = ["All", "10m", "6m", "2m", "70cm", "23cm"]
    private let usStates = [
        "Alabama","Alaska","Arizona","Arkansas","California","Colorado","Connecticut",
        "Delaware","Florida","Georgia","Hawaii","Idaho","Illinois","Indiana","Iowa",
        "Kansas","Kentucky","Louisiana","Maine","Maryland","Massachusetts","Michigan",
        "Minnesota","Mississippi","Missouri","Montana","Nebraska","Nevada",
        "New Hampshire","New Jersey","New Mexico","New York","North Carolina",
        "North Dakota","Ohio","Oklahoma","Oregon","Pennsylvania","Rhode Island",
        "South Carolina","South Dakota","Tennessee","Texas","Utah","Vermont",
        "Virginia","Washington","West Virginia","Wisconsin","Wyoming"
    ]

    var body: some View {
        VStack(spacing: 0) {
            // Title bar
            HStack {
                Text("Find Repeaters")
                    .font(.headline)
                    .accessibilityAddTraits(.isHeader)
                Spacer()
                Button("Close") { dismiss() }
                    .accessibilityLabel("Close repeater search")
            }
            .padding()

            Divider()

            // Search controls
            Form {
                Section("Search") {
                    Picker("State", selection: $selectedState) {
                        ForEach(usStates, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.menu)
                    .accessibilityLabel("US state to search")

                    LabeledContent("County (optional)") {
                        TextField("e.g. Travis", text: $county)
                            .frame(width: 160)
                    }
                    .accessibilityLabel("County filter, optional")

                    Picker("Band", selection: $selectedBand) {
                        ForEach(bandOptions, id: \.self) { Text($0).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .accessibilityLabel("Band filter")

                    Button {
                        Task { await search() }
                    } label: {
                        if isSearching {
                            HStack(spacing: 6) {
                                ProgressView().controlSize(.small)
                                Text("Searching…")
                            }
                        } else {
                            Label("Search", systemImage: "magnifyingglass")
                        }
                    }
                    .disabled(isSearching)
                    .accessibilityLabel("Search RepeaterBook")
                }
            }
            .formStyle(.grouped)
            .frame(height: 220)

            Divider()

            // Error
            if let err = errorMessage {
                Text(err)
                    .font(.caption)
                    .foregroundStyle(.red)
                    .padding(.horizontal)
                    .padding(.top, 4)
                    .accessibilityLabel("Search error: \(err)")
            }

            // Results
            if results.isEmpty && !isSearching {
                VStack(spacing: 8) {
                    Image(systemName: "antenna.radiowaves.left.and.right")
                        .font(.largeTitle)
                        .foregroundStyle(.secondary)
                        .accessibilityHidden(true)
                    Text(errorMessage == nil ? "Search above to find repeaters." : "No results.")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                List(results) { entry in
                    RepeaterRow(entry: entry, isSelected: selectionBinding(for: entry))
                }
                .listStyle(.plain)
                .accessibilityLabel("Repeater results, \(results.count) found")
            }

            Divider()

            // Bottom bar
            HStack {
                Button("Select All") {
                    results.forEach { selections[$0.id] = true }
                }
                .disabled(results.isEmpty)
                .accessibilityLabel("Select all repeaters")

                Button("Select None") {
                    results.forEach { selections[$0.id] = false }
                }
                .disabled(results.isEmpty)
                .accessibilityLabel("Deselect all repeaters")

                Spacer()

                let count = selections.values.filter { $0 }.count
                Button("Import \(count) Selected") {
                    let toImport = results.filter { selections[$0.id] == true }
                    store.importRepeaters(toImport)
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .disabled(count == 0 || store.memoryMap == nil)
                .accessibilityLabel("Import \(count) selected repeaters into empty channel slots")
                .accessibilityHint(store.memoryMap == nil ? "No memory image loaded" : "")
            }
            .padding()
        }
        .frame(minWidth: 560, minHeight: 580)
    }

    // MARK: - Helpers

    private func selectionBinding(for entry: RepeaterEntry) -> Binding<Bool> {
        Binding(
            get: { selections[entry.id] ?? true },
            set: { selections[entry.id] = $0 }
        )
    }

    private func search() async {
        isSearching   = true
        errorMessage  = nil
        let band = selectedBand == "All" || selectedBand.isEmpty ? nil : selectedBand
        do {
            let found = try await store.searchRepeaterBook(
                state:  selectedState,
                county: county.isEmpty ? nil : county,
                band:   band
            )
            results    = found
            selections = Dictionary(uniqueKeysWithValues: found.map { ($0.id, true) })
            if found.isEmpty { errorMessage = "No repeaters found for these criteria." }
            store.announceAccessibility("Found \(found.count) repeaters in \(selectedState).")
        } catch {
            errorMessage = error.localizedDescription
            store.announceAccessibility("Search failed: \(error.localizedDescription)")
        }
        isSearching = false
    }
}

// MARK: - Repeater row

private struct RepeaterRow: View {
    let entry: RepeaterEntry
    @Binding var isSelected: Bool

    var body: some View {
        HStack(spacing: 8) {
            Toggle("", isOn: $isSelected)
                .labelsHidden()
                .accessibilityLabel(isSelected ? "Deselect \(entry.callsign)" : "Select \(entry.callsign)")

            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.callsign)
                        .font(.body.bold())
                    Text(entry.city)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    if let use = entry.use, use.uppercased() != "OPEN" {
                        Text(use)
                            .font(.caption2)
                            .foregroundStyle(.orange)
                    }
                }
                HStack(spacing: 8) {
                    Text(entry.frequency)
                        .font(.caption.monospacedDigit())
                    if let off = entry.offset, !off.isEmpty {
                        Text(off)
                            .font(.caption.monospacedDigit())
                            .foregroundStyle(.secondary)
                    }
                    if entry.ctcssHz > 0 {
                        Text(String(format: "%.1f Hz", entry.ctcssHz))
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    } else {
                        Text("No tone")
                            .font(.caption)
                            .foregroundStyle(.tertiary)
                    }
                }
            }
            Spacer()
        }
        .padding(.vertical, 2)
        .accessibilityElement(children: .combine)
        .accessibilityLabel(rowLabel)
    }

    private var rowLabel: String {
        let sel  = isSelected ? "Selected" : "Not selected"
        let tone = entry.ctcssHz > 0 ? String(format: "%.1f hertz tone", entry.ctcssHz) : "no tone"
        return "\(entry.callsign), \(entry.city), \(entry.frequency) megahertz, \(tone). \(sel)."
    }
}
