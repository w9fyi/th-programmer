// ContentView.swift — Root window: tab navigation + global toolbar

import SwiftUI

struct ContentView: View {
    @EnvironmentObject var store: RadioStore

    enum Tab: Int, CaseIterable {
        case memories, callChannels, scanEdges, weather, drRepeaters, hotspots, reflector

        var title: String {
            switch self {
            case .memories:     return "Memories"
            case .callChannels: return "Call Channels"
            case .scanEdges:    return "Scan Edges"
            case .weather:      return "Weather"
            case .drRepeaters:  return "DR Repeaters"
            case .hotspots:     return "Hotspots"
            case .reflector:    return "Reflector"
            }
        }

        var icon: String {
            switch self {
            case .memories:     return "memorychip"
            case .callChannels: return "phone.fill"
            case .scanEdges:    return "waveform.path.ecg"
            case .weather:      return "cloud.rain.fill"
            case .drRepeaters:  return "dot.radiowaves.up.forward"
            case .hotspots:     return "wifi"
            case .reflector:    return "antenna.radiowaves.left.and.right"
            }
        }
    }

    @State private var selectedTab: Tab = .memories

    var body: some View {
        VStack(spacing: 0) {
            NavigationStack {
                TabView(selection: $selectedTab) {
                    ChannelListView()
                        .tabItem { Label("Memories", systemImage: Tab.memories.icon) }
                        .tag(Tab.memories)

                    CallChannelView()
                        .tabItem { Label("Call Channels", systemImage: Tab.callChannels.icon) }
                        .tag(Tab.callChannels)

                    ScanEdgeView()
                        .tabItem { Label("Scan Edges", systemImage: Tab.scanEdges.icon) }
                        .tag(Tab.scanEdges)

                    WeatherChannelView()
                        .tabItem { Label("Weather", systemImage: Tab.weather.icon) }
                        .tag(Tab.weather)

                    DRRepeaterView()
                        .tabItem { Label("DR Repeaters", systemImage: Tab.drRepeaters.icon) }
                        .tag(Tab.drRepeaters)

                    HotspotView()
                        .tabItem { Label("Hotspots", systemImage: Tab.hotspots.icon) }
                        .tag(Tab.hotspots)

                    ReflectorView()
                        .tabItem { Label("Reflector", systemImage: Tab.reflector.icon) }
                        .tag(Tab.reflector)
                }
                .navigationTitle("TH-D75 — \(selectedTab.title)")
                .toolbar { globalToolbar }
            }

            if let detected = store.detectedRadio {
                Divider()
                detectionBanner(detected)
            }

            Divider()
            statusBar
                .padding(.horizontal, 12)
                .padding(.vertical, 5)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .alert("Error", isPresented: errorPresented, actions: {
            Button("OK", role: .cancel) { store.errorMessage = nil }
        }, message: {
            Text(store.errorMessage ?? "")
        })
        .sheet(isPresented: $store.showingRepeaterBook) {
            RepeaterBookView()
                .environmentObject(store)
        }
        .sheet(isPresented: $store.showingLiveControl) {
            LiveControlSheet()
                .environmentObject(store)
        }
        .frame(minWidth: 700, minHeight: 500)
    }

    // MARK: - Global toolbar

    @ToolbarContentBuilder
    private var globalToolbar: some ToolbarContent {
        ToolbarItemGroup(placement: .primaryAction) {
            Button {
                store.showingRepeaterBook = true
            } label: {
                Label("Find Repeaters", systemImage: "magnifyingglass.circle")
            }
            .disabled(store.memoryMap == nil || store.isBusy)
            .accessibilityLabel("Find repeaters via RepeaterBook")
            .accessibilityHint("Search and import repeaters into empty channels")
            .help("Search RepeaterBook and import repeaters")

            Divider()

            Button {
                Task { await store.downloadFromRadio() }
            } label: {
                Label("Download", systemImage: "arrow.down.circle")
            }
            .disabled(store.portPath.isEmpty || store.isBusy)
            .accessibilityLabel("Download memory from radio")
            .accessibilityHint("Reads all channels from the TH-D75 via USB or Bluetooth")
            .help("Download from radio")

            Button {
                Task { await store.uploadToRadio() }
            } label: {
                Label("Upload", systemImage: "arrow.up.circle")
            }
            .disabled(store.portPath.isEmpty || store.memoryMap == nil || store.isBusy)
            .accessibilityLabel("Upload memory to radio")
            .accessibilityHint("Writes all channels to the TH-D75 via USB or Bluetooth")
            .help("Upload to radio")

            Divider()

            liveToolbarItem
        }
    }

    @ViewBuilder
    private var liveToolbarItem: some View {
        if store.liveConnected {
            Button {
                store.showingLiveControl = true
            } label: {
                Label(store.liveState?.frequencyMHz ?? "Live", systemImage: "dot.radiowaves.left.and.right")
            }
            .accessibilityLabel("Live control connected. Frequency: \(store.liveState?.frequencyMHz ?? "unknown") megahertz. Activate to open live control panel.")
            .help("Open live control panel")
        } else {
            Button {
                Task { await store.connectLive() }
            } label: {
                Label("Live", systemImage: "dot.radiowaves.left.and.right")
            }
            .disabled(store.portPath.isEmpty || store.isBusy)
            .accessibilityLabel("Connect live radio control")
            .accessibilityHint("Opens real-time CAT command session")
            .help("Connect live CAT control")
        }
    }

    // MARK: - Detection banner

    private func detectionBanner(_ detected: RadioStore.RadioDetection) -> some View {
        HStack(spacing: 10) {
            Image(systemName: detected.via == .usb ? "cable.connector" : "dot.radiowaves.left.and.right")
                .foregroundStyle(Color.accentColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 1) {
                Text("\(detected.model) detected")
                    .font(.callout.weight(.medium))
                Text(URL(fileURLWithPath: detected.port).lastPathComponent)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }

            Spacer()

            Button("Select Port") { store.selectDetectedRadio() }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .accessibilityLabel("Select \(detected.model) on \(URL(fileURLWithPath: detected.port).lastPathComponent)")

            Button {
                store.dismissDetectedRadio()
            } label: {
                Image(systemName: "xmark")
                    .font(.caption.weight(.bold))
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Dismiss radio detection banner")
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(Color.accentColor.opacity(0.08))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(detected.model) detected via \(detected.via == .usb ? "USB" : "Bluetooth"), port \(URL(fileURLWithPath: detected.port).lastPathComponent)")
    }

    // MARK: - Status bar

    @ViewBuilder
    private var statusBar: some View {
        if store.isBusy, let p = store.progress {
            HStack(spacing: 8) {
                ProgressView(value: p.fraction)
                    .frame(width: 140)
                    .accessibilityLabel(p.message)
                    .accessibilityValue("\(p.current) of \(p.total) blocks")
                Text("\(p.message) — \(Int(p.fraction * 100))%")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            }
        } else {
            Text(store.statusMessage)
                .font(.caption)
                .foregroundStyle(.secondary)
                .accessibilityLabel("Status: \(store.statusMessage)")
        }
    }

    // MARK: - Helpers

    private var errorPresented: Binding<Bool> {
        Binding(
            get: { store.errorMessage != nil },
            set: { if !$0 { store.errorMessage = nil } }
        )
    }
}
