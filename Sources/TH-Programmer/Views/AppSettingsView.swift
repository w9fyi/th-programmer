// AppSettingsView.swift — Cmd+, settings window: 4 tabs

import SwiftUI
import Combine

struct AppSettingsView: View {
    var body: some View {
        TabView {
            CommunicationSettingsView()
                .tabItem { Label("Communication", systemImage: "cable.connector") }

            RadioSettingsTabContent()
                .tabItem { Label("Radio", systemImage: "radio") }

            APRSSettingsView()
                .tabItem { Label("APRS", systemImage: "location.circle") }

            DSTARSettingsView()
                .tabItem { Label("D-STAR", systemImage: "dot.radiowaves.left.and.right") }
        }
        .frame(minWidth: 600, minHeight: 480)
    }
}

// MARK: - Radio tab wrapper (manages its own state, save button at bottom)

private struct RadioSettingsTabContent: View {
    @EnvironmentObject var store: RadioStore
    @State private var settings: RadioSettings = RadioSettings(from: Data())
    @State private var original: RadioSettings = RadioSettings(from: Data())

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                RadioSettingsForm(settings: $settings)
                    .padding(.bottom, 8)
            }
            Divider()
            HStack {
                Button("Revert") {
                    settings = original
                    store.announceAccessibility("Radio settings reverted.")
                }
                .disabled(settings == original)
                .accessibilityLabel("Revert radio settings to last saved values")
                Spacer()
                Button("Save") {
                    store.applyRadioSettings(settings)
                    original = settings
                }
                .buttonStyle(.borderedProminent)
                .disabled(store.memoryMap == nil || settings == original)
                .accessibilityLabel("Save radio settings to memory image")
            }
            .padding(12)
        }
        .onAppear { loadSettings() }
        .onReceive(store.$memoryMap) { _ in loadSettings() }
    }

    private func loadSettings() {
        guard let map = store.memoryMap else { return }
        let s = map.radioSettings()
        settings = s
        original = s
    }
}
