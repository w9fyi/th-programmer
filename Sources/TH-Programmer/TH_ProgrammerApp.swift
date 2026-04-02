// TH_ProgrammerApp.swift — @main entry point

import SwiftUI
import AppKit

@main
struct TH_ProgrammerApp: App {

    @StateObject private var store = RadioStore()
    @StateObject private var reflectorStore = ReflectorStore()
    @StateObject private var reflectorDirectory = ReflectorDirectory()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .environmentObject(reflectorStore)
                .environmentObject(reflectorDirectory)
        }
        .commands {
            CommandGroup(replacing: .newItem) { }   // suppress File > New
            CommandGroup(after: .newItem) {
                Button("Open…") { openPanel() }
                    .keyboardShortcut("o")

                Button("Save As…") { savePanel() }
                    .keyboardShortcut("s", modifiers: [.command, .shift])
                    .disabled(store.memoryMap == nil)
            }

            CommandMenu("Reflector") {
                Button("Browse Reflectors…") {
                    reflectorStore.showDirectory = true
                }
                .keyboardShortcut("b")

                Button("Connect") {
                    // Connect to last favorite if available
                    if let first = reflectorStore.favoritesManager.favorites.first {
                        reflectorStore.connectToFavorite(first)
                    }
                }
                .keyboardShortcut("k")
                .disabled(reflectorStore.connectionState != .disconnected
                          || reflectorStore.favoritesManager.favorites.isEmpty)

                Button("Disconnect") {
                    reflectorStore.disconnect()
                }
                .keyboardShortcut("d")
                .disabled(reflectorStore.connectionState == .disconnected)

                Divider()

                Button("Add to Favorites…") {
                    reflectorStore.showAddFavoriteFromMenu = true
                }
                .keyboardShortcut("f")
                .disabled(reflectorStore.connectionState != .connected)
            }

            CommandMenu("Radio") {
                Button("Download from Radio") {
                    Task { await store.downloadFromRadio() }
                }
                .keyboardShortcut("d", modifiers: [.command, .shift])
                .disabled(store.portPath.isEmpty || store.isBusy)

                Button("Upload to Radio") {
                    Task { await store.uploadToRadio() }
                }
                .keyboardShortcut("u", modifiers: [.command, .shift])
                .disabled(store.portPath.isEmpty || store.memoryMap == nil || store.isBusy)

                Divider()

                Button("Find Repeaters…") {
                    store.showingRepeaterBook = true
                }
                .keyboardShortcut("r", modifiers: [.command, .shift])
                .disabled(store.memoryMap == nil)

                Divider()

                Button("Next Channel") {
                    selectAdjacentChannel(direction: 1)
                }
                .keyboardShortcut(.downArrow, modifiers: .command)
                .disabled(store.memoryMap == nil)

                Button("Previous Channel") {
                    selectAdjacentChannel(direction: -1)
                }
                .keyboardShortcut(.upArrow, modifiers: .command)
                .disabled(store.memoryMap == nil)
            }
        }

        Settings {
            AppSettingsView()
                .environmentObject(store)
        }
    }

    // MARK: - Open / Save panels

    private func openPanel() {
        let panel = NSOpenPanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.message = "Open a TH-D74 or TH-D75 memory file (.d74 / .d75)"
        panel.prompt = "Open"
        if panel.runModal() == .OK, let url = panel.url {
            store.loadFile(url: url)
        }
    }

    private func savePanel() {
        let panel = NSSavePanel()
        panel.allowedContentTypes = []
        panel.allowsOtherFileTypes = true
        panel.nameFieldStringValue = "memory.d75"
        panel.message = "Save memory image"
        panel.prompt = "Save"
        if panel.runModal() == .OK, let url = panel.url {
            store.saveFile(url: url)
        }
    }

    private func selectAdjacentChannel(direction: Int) {
        let channels = store.channels.filter { !$0.empty }
        guard !channels.isEmpty else { return }
        if let current = store.selectedNumber,
           let idx = channels.firstIndex(where: { $0.number == current }) {
            let newIdx = (idx + direction + channels.count) % channels.count
            store.selectedNumber = channels[newIdx].number
        } else {
            store.selectedNumber = direction > 0 ? channels.first?.number : channels.last?.number
        }
    }
}
