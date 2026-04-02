// ReflectorDirectorySheet.swift — Searchable reflector browser sheet

import SwiftUI

struct ReflectorDirectorySheet: View {
    @EnvironmentObject var reflectorStore: ReflectorStore
    @ObservedObject var directory: ReflectorDirectory
    @Environment(\.dismiss) private var dismiss

    @State private var expandedReflectorID: String?

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Reflector Directory")
                    .font(.title2.bold())
                Spacer()
                Button("Done") {
                    dismiss()
                }
                .keyboardShortcut(.escape, modifiers: [])
                .accessibilityLabel("Close directory")
            }
            .padding()

            Divider()

            // Search and filter
            VStack(spacing: 8) {
                TextField("Search reflectors…", text: $directory.searchText)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityLabel("Search reflectors")
                    .accessibilityHint("Filter by reflector name, number, country, or description")

                Picker("Type Filter", selection: $directory.typeFilter) {
                    Text("All").tag(ReflectorTarget.ReflectorType?.none)
                    ForEach(ReflectorTarget.ReflectorType.allCases) { type in
                        Text(type.rawValue).tag(ReflectorTarget.ReflectorType?.some(type))
                    }
                }
                .pickerStyle(.segmented)
                .accessibilityLabel("Reflector type filter")
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Reflector list
            if directory.isLoading {
                Spacer()
                ProgressView("Loading reflectors…")
                    .accessibilityLabel("Loading reflector directory")
                Spacer()
            } else if let error = directory.errorMessage {
                Spacer()
                VStack(spacing: 12) {
                    Text(error)
                        .foregroundStyle(.red)
                        .accessibilityLabel("Error: \(error)")
                    Button("Retry") {
                        Task { await directory.forceRefresh() }
                    }
                    .accessibilityLabel("Retry loading directory")
                }
                Spacer()
            } else if directory.filteredReflectors.isEmpty {
                Spacer()
                Text("No reflectors match your search.")
                    .foregroundStyle(.secondary)
                    .accessibilityLabel("No reflectors match your search")
                Spacer()
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 1) {
                        ForEach(directory.filteredReflectors) { reflector in
                            reflectorRow(reflector)
                        }
                    }
                }
            }
        }
        .frame(minWidth: 500, minHeight: 400)
        .task {
            await directory.refresh()
        }
    }

    // MARK: - Reflector Row

    private func reflectorRow(_ reflector: ReflectorDirectory.ReflectorInfo) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Button(action: {
                withAnimation {
                    if expandedReflectorID == reflector.id {
                        expandedReflectorID = nil
                    } else {
                        expandedReflectorID = reflector.id
                    }
                }
            }) {
                HStack {
                    VStack(alignment: .leading, spacing: 2) {
                        Text(reflector.id)
                            .font(.body.monospaced().bold())
                        if !reflector.country.isEmpty || !reflector.description.isEmpty {
                            Text([reflector.country, reflector.description].filter { !$0.isEmpty }.joined(separator: " — "))
                                .font(.caption)
                                .foregroundStyle(.secondary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Image(systemName: expandedReflectorID == reflector.id ? "chevron.up" : "chevron.down")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("\(reflector.id)\(reflector.country.isEmpty ? "" : ", \(reflector.country)")\(reflector.description.isEmpty ? "" : ", \(reflector.description)")")
            .accessibilityHint("Expand to see modules and connect")

            if expandedReflectorID == reflector.id {
                moduleGrid(for: reflector)
                    .padding(.leading, 16)
                    .padding(.vertical, 4)
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 6)
        .background(Color.gray.opacity(0.05))
    }

    // MARK: - Module Grid

    private func moduleGrid(for reflector: ReflectorDirectory.ReflectorInfo) -> some View {
        let columns = Array(repeating: GridItem(.flexible(), spacing: 4), count: 13)
        return LazyVGrid(columns: columns, spacing: 4) {
            ForEach(reflector.modules) { mod in
                Button(String(mod.letter)) {
                    let target = ReflectorTarget(type: reflector.type, number: reflector.number, module: mod.letter)
                    reflectorStore.connect(to: target)
                    dismiss()
                }
                .buttonStyle(.bordered)
                .font(.caption.monospaced())
                .disabled(reflectorStore.connectionState != .disconnected)
                .accessibilityLabel("Module \(String(mod.letter))")
                .accessibilityHint("Connect to \(reflector.id) module \(String(mod.letter))")
            }
        }
    }
}
