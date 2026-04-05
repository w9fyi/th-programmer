// RadioStore.swift — Main ViewModel; drives all views

import Foundation
import SwiftUI
import AppKit

@MainActor
final class RadioStore: ObservableObject {

    // MARK: - Published State

    @Published var memoryMap: MemoryMap?
    @Published var selectedNumber: Int?
    @Published var portPath: String = ""
    @Published var availablePorts: [String] = []

    @Published private(set) var isBusy = false
    @Published private(set) var progress: CloneProgress?
    @Published var errorMessage: String?
    @Published var statusMessage: String = "No image loaded."

    // Dirty-tracking: set is numbers of channels modified since last upload
    @Published private(set) var modifiedChannels: Set<Int> = []

    @Published var showingRadioSettings = false
    @Published var showingRepeaterBook  = false

    // MARK: - Radio auto-detection

    struct RadioDetection: Equatable {
        let port: String
        let model: String       // "TH-D74" or "TH-D75"
        let via: Via
        enum Via { case usb, bluetooth }
    }
    @Published var detectedRadio: RadioDetection?

    // MARK: - Live CAT state
    @Published private(set) var liveConnected = false
    @Published private(set) var liveState: LiveRadioState?
    @Published var showingLiveControl = false

    // Live-settable radio settings (fetched once on connect, updated on user change)
    @Published private(set) var afGain: UInt8 = 69
    @Published private(set) var backlight: UInt8 = 2       // LC: 0=manual,1=on,2=auto,3=DC-in
    @Published private(set) var barAntenna: UInt8 = 1      // BS: 0=external,1=internal
    @Published private(set) var powerSave: UInt8 = 0       // PS: read-only via CAT
    @Published private(set) var voxOn: Bool = false
    @Published private(set) var voxGain: UInt8 = 4         // VG: 0–9
    @Published private(set) var voxDelay: UInt8 = 1        // VD: 0–6
    @Published private(set) var dualBand: Bool = true      // DL: true=dual, false=single
    @Published private(set) var attenuatorA: Bool = false   // RA 0
    @Published private(set) var attenuatorB: Bool = false   // RA 1
    @Published private(set) var sMeterA: UInt8 = 0          // SM 0 (polled)
    @Published private(set) var sMeterB: UInt8 = 0          // SM 1 (polled)
    @Published private(set) var tuningStepA: UInt8 = 0      // SF 0 (polled)
    @Published private(set) var tuningStepB: UInt8 = 0      // SF 1 (polled)
    @Published private(set) var vfoMemModeA: UInt8 = 0      // VM 0: 0=VFO,1=MR,2=Call,3=DV
    @Published private(set) var vfoMemModeB: UInt8 = 0      // VM 1
    @Published private(set) var memoryChannelA: UInt16? = nil // MR 0 (nil if not in MR mode)
    @Published private(set) var tncMode: UInt8 = 0           // TN: 0=off, 1=APRS
    @Published private(set) var tncBand: UInt8 = 0           // TN band
    @Published private(set) var beaconMode: UInt8 = 0        // PT: 0=manual,1=PTT,2=auto,3=smart
    @Published private(set) var positionSource: UInt8 = 0    // MS: 0=GPS,1-5=stored

    // TX power per band (0=High, 1=Medium, 2=Low, 3=EL)
    @Published private(set) var txPowerA: UInt8 = 0
    @Published private(set) var txPowerB: UInt8 = 0

    // D-STAR reflector status
    @Published private(set) var reflectorStatus: String = ""

    // Display-only radio info (serial, firmware, callsign, clock, GPS)
    @Published private(set) var radioInfo: RadioInfoState?

    private var liveConnection: THD75LiveConnection?
    private var pollTask: Task<Void, Never>?

    private let usbDetector = USBRadioDetector()

    let bluetooth = BluetoothManager()

    // Progress milestone tracking — reset at start of each operation
    private var progressMilestone = -1

    // MARK: - Init

    init() {
        availablePorts = SerialPort.availablePorts()
        portPath = Self.preferredPort(from: availablePorts)
        startDetection()
    }

    nonisolated deinit {}

    // MARK: - Computed

    var channels: [ChannelMemory] {
        guard let map = memoryMap else { return [] }
        return (0..<CHANNEL_COUNT).map { map.channel(number: $0) }
    }

    var extendedChannels: [ChannelMemory] {
        guard let map = memoryMap else { return [] }
        return (1000..<TOTAL_CHANNEL_SLOTS).compactMap { i in
            let ch = map.channel(number: i)
            return ch.extdNumber != nil ? ch : nil
        }
    }

    var groups: [ChannelGroup] {
        memoryMap?.allGroups() ?? []
    }

    var selectedChannel: Binding<ChannelMemory?> {
        Binding(
            get: { [weak self] in
                guard let self, let n = self.selectedNumber, let map = self.memoryMap else { return nil }
                return map.channel(number: n)
            },
            set: { [weak self] newValue in
                guard let self, let ch = newValue else { return }
                self.memoryMap?.setChannel(ch)
                self.modifiedChannels.insert(ch.number)
            }
        )
    }

    // MARK: - Auto-detection

    private func startDetection() {
        usbDetector.onDetected = { [weak self] radio in
            guard let self else { return }
            // Don't re-announce if we already show this port
            guard self.detectedRadio?.port != radio.port else { return }
            self.detectedRadio = RadioDetection(port: radio.port, model: radio.model, via: .usb)
            self.refreshPorts()
            self.announceAccessibility("\(radio.model) detected via USB. Activate the banner to select it.")
        }
        usbDetector.onRemoved = { [weak self] in
            guard let self else { return }
            self.refreshPorts()
            if let detected = self.detectedRadio,
               !self.availablePorts.contains(detected.port) {
                self.detectedRadio = nil
            }
        }
        usbDetector.start()

        bluetooth.onRadioConnected = { [weak self] radio in
            guard let self, let port = radio.portPath else { return }
            guard self.detectedRadio?.port != port else { return }
            self.detectedRadio = RadioDetection(port: port, model: radio.name, via: .bluetooth)
            self.refreshPorts()
            self.announceAccessibility("\(radio.name) detected via Bluetooth. Activate the banner to select it.")
        }
        bluetooth.startMonitoringConnections()
    }

    /// Select the detected port and dismiss the banner.
    func selectDetectedRadio() {
        guard let detected = detectedRadio else { return }
        portPath = detected.port
        detectedRadio = nil
        statusMessage = "\(detected.model) selected on \(URL(fileURLWithPath: detected.port).lastPathComponent)."
        announceAccessibility("\(detected.model) selected.")
    }

    /// Dismiss the detection banner without selecting the port.
    func dismissDetectedRadio() {
        detectedRadio = nil
    }

    // MARK: - Refresh port list

    func refreshPorts() {
        availablePorts = SerialPort.availablePorts()
        bluetooth.refreshPaired()
        if !availablePorts.contains(portPath) {
            portPath = Self.preferredPort(from: availablePorts)
        }
    }

    /// Pick the best default port: prefer usbmodem (TH-D75 USB cable) over everything else.
    private static func preferredPort(from ports: [String]) -> String {
        ports.first { $0.contains("usbmodem") } ?? ports.first ?? ""
    }

    // MARK: - Bluetooth connect

    /// Connect to a paired TH-D75 over Bluetooth, wait for the virtual serial
    /// port to appear, then select it automatically.
    func connectBluetooth(_ radio: BluetoothRadio) async {
        isBusy = true
        statusMessage = "Connecting to \(radio.name) via Bluetooth…"
        errorMessage = nil

        if let path = await bluetooth.connect(radio) {
            refreshPorts()
            portPath = path
            statusMessage = "Bluetooth connected — \(URL(fileURLWithPath: path).lastPathComponent)"
            announceAccessibility("Bluetooth connected.")
        } else {
            errorMessage = "Could not find serial port for \(radio.name). " +
                           "Make sure Bluetooth is on (Menu 930) and the radio is paired."
            statusMessage = "Bluetooth connection failed."
        }
        isBusy = false
    }

    // MARK: - Download from radio

    func downloadFromRadio() async {
        guard !portPath.isEmpty else {
            errorMessage = "No serial port selected."
            return
        }
        isBusy = true
        progressMilestone = -1
        progress = CloneProgress(message: "Connecting…", current: 0, total: 1)
        errorMessage = nil
        do {
            let map = try await THD75Connection.asyncDownload(portPath: portPath) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p
                    let milestone = Int(p.fraction * 4)  // 0–3 → 0%, 25%, 50%, 75%
                    if milestone > self.progressMilestone && milestone > 0 {
                        self.progressMilestone = milestone
                        self.announceAccessibility("Downloading: \(milestone * 25) percent complete")
                    }
                }
            }
            memoryMap = map
            modifiedChannels = []
            statusMessage = "Downloaded from radio at \(portPath)."
            progress = nil
            announceAccessibility("Download complete.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Download failed."
            progress = nil
        }
        isBusy = false
    }

    // MARK: - Protocol diagnostic

    func diagnoseRadio() async {
        guard !portPath.isEmpty else {
            errorMessage = "No serial port selected."
            return
        }
        isBusy = true
        progress = CloneProgress(message: "Running diagnostic…", current: 0, total: 1)
        errorMessage = nil
        statusMessage = "Diagnostic running — see /tmp/thd75_swift.log"
        do {
            try await THD75Connection.asyncDiagnose(portPath: portPath)
            statusMessage = "Diagnostic complete — open /tmp/thd75_swift.log"
            announceAccessibility("Protocol diagnostic complete. Check log file at /tmp/thd75_swift.log")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Diagnostic failed: \(error.localizedDescription)"
        }
        progress = nil
        isBusy = false
    }

    // MARK: - Upload to radio

    func uploadToRadio() async {
        guard !portPath.isEmpty else {
            errorMessage = "No serial port selected."
            return
        }
        guard let map = memoryMap else {
            errorMessage = "No memory image loaded."
            return
        }
        isBusy = true
        progressMilestone = -1
        progress = CloneProgress(message: "Connecting…", current: 0, total: 1)
        errorMessage = nil
        do {
            try await THD75Connection.asyncUpload(portPath: portPath, map: map) { [weak self] p in
                Task { @MainActor [weak self] in
                    guard let self else { return }
                    self.progress = p
                    let milestone = Int(p.fraction * 4)
                    if milestone > self.progressMilestone && milestone > 0 {
                        self.progressMilestone = milestone
                        self.announceAccessibility("Uploading: \(milestone * 25) percent complete")
                    }
                }
            }
            modifiedChannels = []
            statusMessage = "Uploaded to radio at \(portPath)."
            progress = nil
            announceAccessibility("Upload complete.")
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Upload failed."
            progress = nil
        }
        isBusy = false
    }

    // MARK: - File I/O

    func loadFile(url: URL) {
        do {
            let map = try MemoryMap.load(from: url)
            memoryMap = map
            modifiedChannels = []
            statusMessage = "Loaded \(url.lastPathComponent)."
            announceAccessibility("File loaded.")
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func saveFile(url: URL) {
        guard let map = memoryMap else {
            errorMessage = "No memory image to save."
            return
        }
        do {
            try map.save(to: url)
            modifiedChannels = []
            statusMessage = "Saved to \(url.lastPathComponent)."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Radio Settings

    /// Commit an edited channel draft back to the memory map and mark it modified.
    func commitChannelEdit(_ channel: ChannelMemory) {
        memoryMap?.setChannel(channel)
        modifiedChannels.insert(channel.number)
        statusMessage = "Channel \(channel.number) updated."
        announceAccessibility("Channel \(channel.number) saved.")

        if liveConnected, !channel.empty, !channel.isExtended {
            Task { await liveWriteChannel(channel) }
        }
    }

    func liveWriteChannel(_ channel: ChannelMemory) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncWriteLiveChannel(channel)
            statusMessage = "Channel \(channel.number) written to radio live."
            announceAccessibility("Channel \(channel.number) sent to radio.")
        } catch {
            errorMessage = "Live write failed: \(error.localizedDescription)"
        }
    }

    func applyRadioSettings(_ settings: RadioSettings) {
        guard memoryMap != nil else { return }
        memoryMap?.setRadioSettings(settings)
        statusMessage = "Radio settings updated."
        announceAccessibility("Radio settings saved to image.")
    }

    func applyAPRSSettings(_ settings: APRSSettings) {
        guard memoryMap != nil else { return }
        memoryMap?.setAPRSSettings(settings)
        statusMessage = "APRS settings updated."
        announceAccessibility("APRS settings saved to image.")
    }

    func applyDSTARSettings(_ settings: DSTARSettings) {
        guard memoryMap != nil else { return }
        memoryMap?.setDSTARSettings(settings)
        statusMessage = "D-STAR settings updated."
        announceAccessibility("D-STAR settings saved to image.")
    }

    // MARK: - RepeaterBook

    func searchRepeaterBook(state: String, county: String? = nil, band: String? = nil) async throws -> [RepeaterEntry] {
        var components = URLComponents(string: "https://www.repeaterbook.com/api/export.php")!
        var items: [URLQueryItem] = [
            URLQueryItem(name: "country", value: "United States"),
            URLQueryItem(name: "state",   value: state),
            URLQueryItem(name: "format",  value: "json"),
        ]
        if let county, !county.isEmpty { items.append(URLQueryItem(name: "county", value: county)) }
        if let band,   !band.isEmpty   { items.append(URLQueryItem(name: "band",   value: band))   }
        components.queryItems = items

        let (data, _) = try await URLSession.shared.data(from: components.url!)
        let decoded   = try JSONDecoder().decode(RepeaterBookResponse.self, from: data)
        return decoded.results ?? []
    }

    func importRepeaters(_ entries: [RepeaterEntry]) {
        guard let map = memoryMap else { return }
        var imported = 0
        for entry in entries {
            guard let slot = (0..<CHANNEL_COUNT).first(where: { map.channel(number: $0).empty }) else { break }
            var ch = ChannelMemory(number: slot)
            ch.name      = String(entry.callsign.prefix(8))
            ch.freq      = entry.rxFreqHz
            ch.offset    = entry.offsetHz
            ch.duplex    = entry.duplexMode
            ch.toneMode  = entry.channelToneMode
            ch.rtone     = entry.ctcssHz > 0 ? entry.ctcssHz : 88.5
            ch.empty     = false
            map.setChannel(ch)
            imported += 1
        }
        memoryMap = map
        statusMessage  = "Imported \(imported) repeater\(imported == 1 ? "" : "s")."
        announceAccessibility("Imported \(imported) repeaters.")
    }

    // MARK: - Live CAT

    func connectLive() async {
        guard !portPath.isEmpty else {
            errorMessage = "No serial port selected."
            return
        }
        guard !liveConnected else { return }
        statusMessage = "Connecting live…"
        errorMessage = nil
        do {
            let conn = try await THD75LiveConnection.asyncConnect(portPath: portPath)
            liveConnection = conn
            liveConnected = true
            // Forward NMEA sentences to the position parser on the main thread
            conn.nmeaHandler = { [weak self] sentence in
                guard let self else { return }
                if let pos = THD75LiveConnection.parseNMEAPosition(sentence) {
                    Task { @MainActor [weak self] in
                        guard let self else { return }
                        if self.radioInfo == nil { self.radioInfo = RadioInfoState() }
                        self.radioInfo?.position = pos
                    }
                }
            }
            statusMessage = "Live connected."
            announceAccessibility("Live control connected.")
            startPolling()
            // Fetch static info and current settings in the background
            Task { await fetchRadioInfo() }
        } catch {
            errorMessage = error.localizedDescription
            statusMessage = "Live connect failed."
        }
    }

    func disconnectLive() {
        isReconnecting = false  // cancel any in-progress reconnect
        stopPolling()
        liveConnection?.disconnect()
        liveConnection = nil
        liveConnected = false
        liveState = nil
        radioInfo = nil
        txPowerA = 0
        txPowerB = 0
        reflectorStatus = ""
        statusMessage = "Live disconnected."
    }

    // MARK: - Radio info + settings fetch

    func fetchRadioInfo() async {
        guard let conn = liveConnection else { return }
        do {
            async let info     = conn.asyncGetRadioInfo()
            async let settings = conn.asyncGetLiveSettings()
            let (i, s) = try await (info, settings)
            afGain      = s.afGain
            backlight   = s.backlight
            barAntenna  = s.barAntenna
            powerSave   = s.powerSave
            voxOn       = s.voxOn
            voxGain     = s.voxGain
            voxDelay    = s.voxDelay
            dualBand    = s.dualBand
            attenuatorA = s.attA
            attenuatorB = s.attB
            radioInfo = i
            // Fetch TX power for both bands
            if let pa = try? await conn.asyncGetTxPower(band: 0) { txPowerA = pa }
            if let pb = try? await conn.asyncGetTxPower(band: 1) { txPowerB = pb }
            // Fetch APRS/TNC state
            if let tn = try? await withCheckedThrowingContinuation({ (c: CheckedContinuation<(mode: UInt8, band: UInt8), Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { c.resume(returning: try conn.getTNCMode()) }
                    catch { c.resume(throwing: error) }
                }
            }) { tncMode = tn.mode; tncBand = tn.band }
            if let pt = try? await withCheckedThrowingContinuation({ (c: CheckedContinuation<UInt8, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { c.resume(returning: try conn.getBeaconMode()) }
                    catch { c.resume(throwing: error) }
                }
            }) { beaconMode = pt }
            if let ms = try? await withCheckedThrowingContinuation({ (c: CheckedContinuation<UInt8, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do { c.resume(returning: try conn.getPositionSource()) }
                    catch { c.resume(throwing: error) }
                }
            }) { positionSource = ms }
        } catch {
            // Non-fatal — radio info is display-only
        }
    }

    // MARK: - Live setting setters

    func setLiveAFGain(_ gain: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetAFGain(gain)
            afGain = gain
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveBacklight(_ mode: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetBacklight(mode)
            backlight = mode
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveBarAntenna(_ value: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetBarAntenna(value)
            barAntenna = value
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveVOX(_ on: Bool) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetVOX(on)
            voxOn = on
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveVOXGain(_ gain: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetVOXGain(gain)
            voxGain = gain
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveVOXDelay(_ delay: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetVOXDelay(delay)
            voxDelay = delay
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveDualBand(_ dual: Bool) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetDualBand(dual)
            dualBand = dual
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveAttenuator(band: UInt8, on: Bool) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetAttenuator(band: band, on: on)
            if band == 0 { attenuatorA = on } else { attenuatorB = on }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveFilterWidth(mode: UInt8, width: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetFilterWidth(mode: mode, width: width)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveTuningStep(band: UInt8, step: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetTuningStep(band: band, step: step)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveVFOMemMode(band: UInt8, mode: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetVFOMemMode(band: band, mode: mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveTNCMode(mode: UInt8, band: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetTNCMode(mode: mode, band: band)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveBeaconMode(_ mode: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetBeaconMode(mode)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLivePositionSource(_ source: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetPositionSource(source)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveCallsign(_ call: String) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetCallsign(call)
            if var info = radioInfo { info.callsign = call.uppercased().prefix(8).description; radioInfo = info }
            statusMessage = "Callsign updated."
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - TX Power

    func setLiveTxPower(band: UInt8, level: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetTxPower(band: band, level: level)
            if band == 0 { txPowerA = level } else { txPowerB = level }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - APRS Beacon

    func triggerAPRSBeacon() async {
        guard let conn = liveConnection else { return }
        do {
            let ok = try await conn.asyncTriggerAPRSBeacon()
            if ok {
                statusMessage = "APRS beacon sent."
                announceAccessibility("APRS beacon sent.")
            } else {
                errorMessage = "APRS beacon failed — TNC may be off."
                announceAccessibility("APRS beacon failed. TNC may be off.")
            }
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - D-STAR Reflector

    /// Send a D-STAR UR call command via slot 6, then restore UR to CQCQCQ
    /// and the previously active slot. All three reflector operations share
    /// this pattern: write UR → select slot 6 → key up → release → restore.
    private func sendReflectorCommand(_ urCall: String, conn: THD75LiveConnection) async throws {
        // Remember the user's active slot so we can restore it afterward.
        let previousSlot = try await conn.asyncGetActiveDStarSlot()
        // Write the command UR call into scratch slot 6 and select it.
        try await conn.asyncSetDStarSlot(6, callsign: urCall)
        try await conn.asyncSetActiveDStarSlot(6)
        // Brief key-up to transmit the D-STAR header with the UR call.
        try await conn.asyncPTT(on: true)
        try await Task.sleep(nanoseconds: 500_000_000)
        try await conn.asyncPTT(on: false)
        // Restore slot 6 to CQCQCQ so normal voice traffic flows through
        // the reflector instead of re-sending the link/unlink command.
        try await conn.asyncSetDStarSlot(6, callsign: "CQCQCQ  ")
        // Restore the user's previously active slot.
        try await conn.asyncSetActiveDStarSlot(previousSlot)
    }

    /// Connect to a D-STAR reflector by writing the UR call into slot 6,
    /// selecting slot 6, briefly keying up, then restoring UR to CQCQCQ.
    func connectReflector(_ target: ReflectorTarget) async {
        guard let conn = liveConnection else { return }
        guard target.isValid else {
            errorMessage = "Invalid reflector: number must be 1–999, module A–Z."
            return
        }
        do {
            reflectorStatus = "Linking to \(target.urCallString)…"
            announceAccessibility("Linking to \(target.type.rawValue) \(target.number), module \(target.module).")
            try await sendReflectorCommand(target.urCallString, conn: conn)
            reflectorStatus = "Link request sent: \(target.urCallString)"
            announceAccessibility("Link request sent to \(target.type.rawValue) \(target.number), module \(target.module).")
        } catch {
            reflectorStatus = "Link failed."
            errorMessage = error.localizedDescription
        }
    }

    /// Disconnect from the current D-STAR reflector.
    func disconnectReflector() async {
        guard let conn = liveConnection else { return }
        do {
            reflectorStatus = "Unlinking…"
            announceAccessibility("Unlinking from reflector.")
            try await sendReflectorCommand(ReflectorTarget.unlinkCall, conn: conn)
            reflectorStatus = "Unlinked."
            announceAccessibility("Unlinked from reflector.")
        } catch {
            reflectorStatus = "Unlink failed."
            errorMessage = error.localizedDescription
        }
    }

    /// Query reflector info.
    func queryReflectorInfo() async {
        guard let conn = liveConnection else { return }
        do {
            reflectorStatus = "Querying reflector info…"
            announceAccessibility("Querying reflector info.")
            try await sendReflectorCommand(ReflectorTarget.infoCall, conn: conn)
            reflectorStatus = "Info request sent — listen for audio response."
            announceAccessibility("Reflector info request sent. Listen for the audio response.")
        } catch {
            reflectorStatus = "Info query failed."
            errorMessage = error.localizedDescription
        }
    }

    func setLiveFrequency(_ hz: Int) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSetFrequency(hz)
            liveState = try await conn.asyncGetVFOState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func stepLiveFrequency(up: Bool) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncStepFrequency(up: up)
            liveState = try await conn.asyncGetVFOState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func setLiveMode(_ mode: UInt8) async {
        guard let conn = liveConnection else { return }
        let vfo = liveState?.vfo ?? 0
        do {
            try await withCheckedThrowingContinuation { (cont: CheckedContinuation<Void, Error>) in
                DispatchQueue.global(qos: .userInitiated).async {
                    do    { try conn.setMode(mode, vfo: vfo); cont.resume(returning: ()) }
                    catch { cont.resume(throwing: error) }
                }
            }
            liveState = try await conn.asyncGetVFOState()
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    func selectLiveVFO(_ vfo: UInt8) async {
        guard let conn = liveConnection else { return }
        do {
            try await conn.asyncSelectVFO(vfo)
            liveState = try await conn.asyncGetVFOState(vfo: vfo)
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    // MARK: - Live polling

    /// Consecutive poll failures before we declare the connection dead.
    private static let maxPollFailures = 3

    /// Whether a live reconnect attempt is in progress.
    private var isReconnecting = false

    private func startPolling() {
        pollTask = Task { [weak self] in
            var consecutiveFailures = 0
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 500_000_000)   // 0.5 s
                guard let self, let conn = self.liveConnection else { break }

                // Non-blocking health check — catches dead BT fd immediately
                // without waiting for a blocking read to timeout.
                let healthy = await withCheckedContinuation { cont in
                    DispatchQueue.global(qos: .userInitiated).async {
                        cont.resume(returning: conn.isHealthy())
                    }
                }
                if !healthy {
                    self.handleLiveDisconnect(reason: "Serial port disconnected")
                    break
                }

                do {
                    let state = try await conn.asyncGetVFOState()
                    let smA = try await conn.asyncGetSMeter(band: 0)
                    let smB = try await conn.asyncGetSMeter(band: 1)
                    // Fetch tuning step and VFO/mem mode (lightweight reads)
                    let sfA = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<UInt8, Error>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do { c.resume(returning: try conn.getTuningStep(band: 0)) }
                            catch { c.resume(throwing: error) }
                        }
                    }
                    let vmA = try? await withCheckedThrowingContinuation { (c: CheckedContinuation<UInt8, Error>) in
                        DispatchQueue.global(qos: .userInitiated).async {
                            do { c.resume(returning: try conn.getVFOMemMode(band: 0)) }
                            catch { c.resume(throwing: error) }
                        }
                    }
                    consecutiveFailures = 0  // reset on success
                    await MainActor.run {
                        self.liveState = state
                        self.sMeterA = smA
                        self.sMeterB = smB
                        if let sf = sfA { self.tuningStepA = sf }
                        if let vm = vmA { self.vfoMemModeA = vm }
                    }
                } catch {
                    consecutiveFailures += 1
                    if consecutiveFailures >= Self.maxPollFailures {
                        self.handleLiveDisconnect(reason: error.localizedDescription)
                        break
                    }
                    // Transient failure — wait a bit longer and retry
                    try? await Task.sleep(nanoseconds: 500_000_000)
                }
            }
        }
    }

    /// Handle a live CAT disconnect — clean up state and attempt reconnect for BT.
    private func handleLiveDisconnect(reason: String) {
        let wasBluetooth = liveConnection?.isBluetooth ?? false
        let savedPortPath = portPath

        liveConnection?.disconnect()
        liveConnection = nil
        liveConnected = false
        liveState = nil

        if wasBluetooth && !isReconnecting {
            statusMessage = "Bluetooth disconnected — reconnecting…"
            announceAccessibility("Bluetooth disconnected. Attempting to reconnect.")
            attemptLiveReconnect(portPath: savedPortPath, attempt: 1)
        } else {
            statusMessage = "Live connection lost: \(reason)"
            announceAccessibility("Live control disconnected.")
        }
    }

    /// Attempt to reconnect a dropped live CAT session (BT only).
    /// Exponential backoff: 2s, 4s, 8s, 16s — max 5 attempts.
    private func attemptLiveReconnect(portPath: String, attempt: Int) {
        guard attempt <= 5 else {
            isReconnecting = false
            statusMessage = "Reconnect failed after 5 attempts."
            announceAccessibility("Could not reconnect to radio.")
            return
        }
        isReconnecting = true
        let delay = min(Double(1 << attempt), 16.0)  // 2, 4, 8, 16, 16
        statusMessage = "Reconnecting (\(attempt)/5) in \(Int(delay))s…"

        Task {
            try? await Task.sleep(nanoseconds: UInt64(delay * 1_000_000_000))
            guard isReconnecting else { return }  // user may have manually reconnected

            // Check if the BT port still exists in /dev
            let portExists = FileManager.default.fileExists(atPath: portPath)
            guard portExists else {
                statusMessage = "Waiting for radio… (\(attempt)/5)"
                announceAccessibility("Waiting for radio to reconnect.")
                attemptLiveReconnect(portPath: portPath, attempt: attempt + 1)
                return
            }

            do {
                let conn = try await THD75LiveConnection.asyncConnect(portPath: portPath)
                liveConnection = conn
                liveConnected = true
                isReconnecting = false
                conn.nmeaHandler = { [weak self] sentence in
                    guard let self else { return }
                    if let pos = THD75LiveConnection.parseNMEAPosition(sentence) {
                        Task { @MainActor [weak self] in
                            guard let self else { return }
                            if self.radioInfo == nil { self.radioInfo = RadioInfoState() }
                            self.radioInfo?.position = pos
                        }
                    }
                }
                statusMessage = "Reconnected to radio."
                announceAccessibility("Live control reconnected.")
                startPolling()
                Task { await fetchRadioInfo() }
            } catch {
                attemptLiveReconnect(portPath: portPath, attempt: attempt + 1)
            }
        }
    }

    private func stopPolling() {
        pollTask?.cancel()
        pollTask = nil
    }

    // MARK: - Helpers

    func announceAccessibility(_ message: String) {
        guard let window = NSApp.keyWindow ?? NSApp.mainWindow else { return }
        NSAccessibility.post(
            element: window,
            notification: .announcementRequested,
            userInfo: [
                NSAccessibility.NotificationUserInfoKey.announcement: message,
                NSAccessibility.NotificationUserInfoKey.priority: NSAccessibilityPriorityLevel.high
            ]
        )
    }
}
