// BluetoothManager.swift — IOBluetooth discovery and connection for TH-D75 SPP

import Foundation
import IOBluetooth
import AppKit

// MARK: - Model

struct BluetoothRadio: Identifiable, Equatable {
    var id: String { addressString }
    var name: String
    var addressString: String
    var isConnected: Bool
    var portPath: String?       // /dev/cu.* once connected, nil until then

    var statusLabel: String {
        if let path = portPath {
            return "Ready — \(URL(fileURLWithPath: path).lastPathComponent)"
        }
        return isConnected ? "Connected (waiting for serial port…)" : "Not connected"
    }
}

// MARK: - Manager

@MainActor
final class BluetoothManager: NSObject, ObservableObject {

    @Published private(set) var radios: [BluetoothRadio] = []
    @Published private(set) var isScanning = false
    @Published private(set) var scanStatus = ""
    @Published private(set) var connectStatus = ""

    private var inquiry: IOBluetoothDeviceInquiry?
    private var foundDevices: [IOBluetoothDevice] = []

    /// Called on the main thread when a paired TH-D74/75 comes in range and connects.
    var onRadioConnected: ((BluetoothRadio) -> Void)?

    private var connectNotification: IOBluetoothUserNotification?

    /// Keep RFCOMM channel alive so the virtual serial port persists.
    /// If this is released, macOS may tear down /dev/cu.TH-D75.
    private(set) var rfcommChannel: IOBluetoothRFCOMMChannel?

    /// Release the held RFCOMM channel so RFCOMMTransport can open channel 2 directly.
    /// Called before direct RFCOMM MMDVM connection — the virtual serial port may disappear.
    func releaseRFCOMMChannel() {
        if let ch = rfcommChannel {
            _ = ch.close()
            ch.setDelegate(nil)
        }
        rfcommChannel = nil
    }

    nonisolated deinit {}

    // MARK: - Public API

    /// Populate `radios` from already-paired devices. Call on appear.
    /// Falls back to checking /dev/ for existing BT serial ports if IOBluetooth
    /// returns nothing (common when TCC permission is invalidated by ad-hoc re-signing).
    func refreshPaired() {
        let allPaired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []

        let supported = allPaired.filter { Self.isSupportedRadio($0) }
        if !supported.isEmpty {
            connectStatus = "Found \(supported.count) TH-D74/D75 device(s)"
            updateRadios(from: supported)
            return
        }

        // Fallback: IOBluetooth returned nothing. Check if /dev/cu.TH-D75 or similar
        // already exists (macOS creates it when the device is connected via System Settings).
        if let fallbackRadio = detectRadioFromDevPorts() {
            radios = [fallbackRadio]
            if fallbackRadio.portPath != nil {
                connectStatus = "Found \(fallbackRadio.name) via serial port (Bluetooth permission not needed)"
            } else {
                connectStatus = "IOBluetooth unavailable — pair and connect via System Settings \u{2192} Bluetooth"
            }
            return
        }

        if allPaired.isEmpty {
            connectStatus = "No paired devices found — pair your radio in System Settings \u{2192} Bluetooth"
        } else {
            let names = allPaired.map { $0.name ?? "(nil)" }
            connectStatus = "Found \(allPaired.count) paired device(s) but none matched TH-D74/D75: \(names.joined(separator: ", "))"
        }
        updateRadios(from: [])
    }

    /// Check /dev/ for existing TH-D74/D75 Bluetooth serial ports.
    /// This works even without IOBluetooth TCC permission.
    /// Uses system_profiler to get the real MAC address for direct RFCOMM.
    private func detectRadioFromDevPorts() -> BluetoothRadio? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else {
            return nil
        }

        let btPort = entries.first { entry in
            guard entry.hasPrefix("cu.") else { return false }
            let lower = entry.lowercased()
            return lower.contains("th-d75") || lower.contains("thd75")
                || lower.contains("th-d74") || lower.contains("thd74")
        }

        guard let btPort else { return nil }
        let path = "/dev/\(btPort)"
        let name = btPort.contains("D75") || btPort.contains("d75") ? "TH-D75" : "TH-D74"

        // Try to get the real MAC address from system_profiler
        // (IOBluetooth TCC may be blocked by ad-hoc signing, but system_profiler works)
        let address = Self.macAddressFromSystemProfiler(radioName: name) ?? "detected-from-dev"

        return BluetoothRadio(
            name: name,
            addressString: address,
            isConnected: true,
            portPath: path
        )
    }

    /// Query system_profiler for the Bluetooth MAC address of a paired radio.
    nonisolated static func macAddressFromSystemProfiler(radioName: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/sbin/system_profiler")
        process.arguments = ["SPBluetoothDataType"]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice

        do {
            try process.run()
            process.waitUntilExit()
        } catch {
            return nil
        }

        guard let data = try? pipe.fileHandleForReading.readDataToEndOfFile(),
              let output = String(data: data, encoding: .utf8) else {
            return nil
        }

        // Parse: look for radioName followed by "Address: XX:XX:XX:XX:XX:XX"
        let lines = output.components(separatedBy: "\n")
        var foundRadio = false
        for line in lines {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix(radioName) && trimmed.hasSuffix(":") {
                foundRadio = true
                continue
            }
            if foundRadio && trimmed.hasPrefix("Address:") {
                let addr = trimmed
                    .replacingOccurrences(of: "Address:", with: "")
                    .trimmingCharacters(in: .whitespaces)
                if addr.contains(":") && addr.count >= 17 {
                    return addr
                }
            }
            // Stop if we hit another device entry
            if foundRadio && !trimmed.hasPrefix("Address") && !trimmed.isEmpty
                && !trimmed.hasPrefix("Minor") && !trimmed.hasPrefix("RSSI")
                && !trimmed.hasPrefix("Services") && !trimmed.hasPrefix("Vendor")
                && !trimmed.hasPrefix("Product") && !trimmed.hasPrefix("Firmware")
                && !trimmed.hasPrefix(radioName) {
                break
            }
        }
        return nil
    }

    /// Register for IOBluetooth connection notifications so we detect a paired
    /// radio the moment it comes in range — no manual scan needed.
    func startMonitoringConnections() {
        guard connectNotification == nil else { return }
        connectNotification = IOBluetoothDevice.register(
            forConnectNotifications: self,
            selector: #selector(bluetoothDeviceConnected(_:device:))
        )
    }

    /// Scan the air for new devices (~10 s). Already-paired devices are also surfaced.
    func startScan() {
        guard !isScanning else { return }
        isScanning = true
        scanStatus = "Scanning…"
        foundDevices = []

        inquiry = IOBluetoothDeviceInquiry(delegate: self)
        inquiry?.inquiryLength = 10
        inquiry?.updateNewDeviceNames = true
        inquiry?.start()
    }

    func stopScan() {
        inquiry?.stop()
    }

    /// Open a Bluetooth connection to the device, establishing the SPP serial port.
    /// Returns the /dev/cu.* path on success, nil on failure.
    ///
    /// Flow:
    ///   1. Open ACL connection
    ///   2. Find SPP service and open RFCOMM channel (triggers /dev/cu.* creation)
    ///   3. Poll up to 10s for the virtual serial port to appear
    func connect(_ radio: BluetoothRadio) async -> String? {
        guard let device = ioBluetoothDevice(for: radio) else {
            connectStatus = "Cannot find device"
            return nil
        }

        // Step 1: Open ACL connection if not already connected.
        // If device reports connected but no serial port exists, the baseband
        // connection is stale (radio was power-cycled). Close it first.
        if device.isConnected() && findPort(for: device) == nil {
            connectStatus = "Closing stale Bluetooth connection…"
            device.closeConnection()
            try? await Task.sleep(nanoseconds: 1_000_000_000)
        }

        if !device.isConnected() {
            connectStatus = "Opening Bluetooth connection…"
            let result = device.openConnection()
            if result != kIOReturnSuccess {
                connectStatus = "ACL connection failed (error \(result))"
                updateRadios(from: activePairedDevices())
                return nil
            }
            // Give macOS time to complete the ACL handshake
            try? await Task.sleep(nanoseconds: 2_000_000_000)
        }

        // Step 2: Try to open RFCOMM channel for SPP to trigger serial port creation
        connectStatus = "Opening serial port service…"
        await openSPPChannel(device: device)

        // Step 3: Poll for the /dev/cu.* port (up to 10s)
        connectStatus = "Waiting for serial port…"
        for attempt in 1...20 {
            if let path = findPort(for: device) {
                connectStatus = "Connected — \(URL(fileURLWithPath: path).lastPathComponent)"
                updateRadios(from: activePairedDevices())
                return path
            }
            if attempt % 4 == 0 {
                connectStatus = "Waiting for serial port… (\(attempt / 2)s)"
            }
            try? await Task.sleep(nanoseconds: 500_000_000)
        }

        connectStatus = "Serial port did not appear. Try turning the radio off and on."
        updateRadios(from: activePairedDevices())
        return nil
    }

    // MARK: - RFCOMM / SPP

    /// Find the SPP service on the device and open an RFCOMM channel.
    /// This triggers macOS to create the /dev/cu.* virtual serial port.
    private nonisolated func openSPPChannel(device: IOBluetoothDevice) async {
        // SPP UUID = 0x1101
        let sppUUID = IOBluetoothSDPUUID(uuid16: 0x1101)

        // Try to find SPP in the device's service records
        var channelID: BluetoothRFCOMMChannelID = 0
        var foundChannel = false

        if let services = device.services as? [IOBluetoothSDPServiceRecord] {
            for service in services {
                if service.hasService(from: [sppUUID as Any]) {
                    if service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                        foundChannel = true
                        break
                    }
                }
            }
        }

        // If we couldn't find SPP in cached SDP records, try performing an SDP query
        if !foundChannel {
            device.performSDPQuery(nil)
            try? await Task.sleep(nanoseconds: 2_000_000_000)

            if let services = device.services as? [IOBluetoothSDPServiceRecord] {
                for service in services {
                    if service.hasService(from: [sppUUID as Any]) {
                        if service.getRFCOMMChannelID(&channelID) == kIOReturnSuccess {
                            foundChannel = true
                            break
                        }
                    }
                }
            }
        }

        // If still no SPP record found, use channel 2 — the TH-D75 uses
        // RFCOMM channel 2 for its data connection (confirmed via d75link binary).
        if !foundChannel {
            channelID = 2
        }

        // Open the RFCOMM channel
        var channel: IOBluetoothRFCOMMChannel?
        var openResult = device.openRFCOMMChannelSync(
            &channel,
            withChannelID: channelID,
            delegate: nil
        )

        // If we get NotPermitted, the macOS TCC Bluetooth permission prompt
        // may be showing. Wait 1s for the user to click Allow, then retry once.
        if openResult != kIOReturnSuccess && openResult == IOReturn(kIOReturnNotPermitted) {
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            channel = nil
            openResult = device.openRFCOMMChannelSync(
                &channel,
                withChannelID: channelID,
                delegate: nil
            )
        }

        if openResult == kIOReturnSuccess, let channel {
            await MainActor.run {
                self.rfcommChannel = channel
            }
        }
        // Even if RFCOMM open fails, the ACL connection may have triggered
        // the port creation on some macOS versions. Continue polling.
    }

    // MARK: - Helpers

    nonisolated static func isSupportedRadio(_ device: IOBluetoothDevice) -> Bool {
        isSupportedRadioName(device.name ?? "")
    }

    /// Pure string test — exposed for unit testing.
    nonisolated static func isSupportedRadioName(_ name: String) -> Bool {
        let upper = name.uppercased()
        return upper.contains("TH-D75") || upper.contains("THD75")
            || upper.contains("TH-D74") || upper.contains("THD74")
    }

    private func ioBluetoothDevice(for radio: BluetoothRadio) -> IOBluetoothDevice? {
        IOBluetoothDevice(addressString: radio.addressString)
    }

    private func activePairedDevices() -> [IOBluetoothDevice] {
        let paired = (IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice]) ?? []
        return paired.filter { Self.isSupportedRadio($0) }
    }

    private func updateRadios(from devices: [IOBluetoothDevice]) {
        radios = devices.map { device in
            BluetoothRadio(
                name: device.name ?? "TH-D75",
                addressString: device.addressString ?? "",
                isConnected: device.isConnected(),
                portPath: findPort(for: device)
            )
        }
    }

    /// Find the /dev/cu.* path for a Bluetooth device by matching its name
    /// or address against the port filename.
    func findPort(for device: IOBluetoothDevice) -> String? {
        let devName = device.name ?? ""
        let addrSuffix = device.addressString?
            .replacingOccurrences(of: ":", with: "-")
            ?? ""

        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev") else {
            return nil
        }

        return entries.sorted()
            .first { entry in
                entry.hasPrefix("cu.") &&
                Self.portEntryMatches(entry, deviceName: devName, addressSuffix: addrSuffix)
            }
            .map { "/dev/\($0)" }
    }

    /// Pure string test — exposed for unit testing.
    nonisolated static func portEntryMatches(_ entry: String, deviceName: String, addressSuffix: String) -> Bool {
        let lower      = entry.lowercased()
        let nameSlug   = deviceName.replacingOccurrences(of: " ", with: "-").lowercased()
        let addrLower  = addressSuffix.lowercased()

        // Direct keyword match (radio name or address in port name)
        if !nameSlug.isEmpty && lower.contains(nameSlug)  { return true }
        if !addrLower.isEmpty && lower.contains(addrLower) { return true }
        // Generic Kenwood port keyword fallback
        return lower.contains("th-d75") || lower.contains("thd75")
            || lower.contains("th-d74") || lower.contains("thd74")
    }
}

// MARK: - IOBluetooth connect notification

extension BluetoothManager {
    /// Fires on the main thread when any Bluetooth device connects.
    /// Filtered to TH-D74/75 only; waits for the virtual serial port then
    /// calls `onRadioConnected`.
    @objc nonisolated func bluetoothDeviceConnected(
        _ notification: IOBluetoothUserNotification,
        device: IOBluetoothDevice
    ) {
        guard Self.isSupportedRadio(device) else { return }
        Task { @MainActor [weak self] in
            guard let self else { return }
            updateRadios(from: activePairedDevices())
            // Poll up to 10s for the virtual serial port to appear
            for _ in 0..<20 {
                if let path = findPort(for: device) {
                    let radio = BluetoothRadio(
                        name: device.name ?? "TH-D75",
                        addressString: device.addressString ?? "",
                        isConnected: true,
                        portPath: path
                    )
                    onRadioConnected?(radio)
                    return
                }
                try? await Task.sleep(nanoseconds: 500_000_000)
            }
        }
    }
}

// MARK: - IOBluetoothDeviceInquiryDelegate

extension BluetoothManager: IOBluetoothDeviceInquiryDelegate {

    nonisolated func deviceInquiryStarted(_ sender: IOBluetoothDeviceInquiry!) {
        Task { @MainActor in scanStatus = "Scanning for devices…" }
    }

    nonisolated func deviceInquiryDeviceFound(_ sender: IOBluetoothDeviceInquiry!,
                                              device: IOBluetoothDevice!) {
        guard let device, Self.isSupportedRadio(device) else { return }
        Task { @MainActor in
            if !foundDevices.contains(device) {
                foundDevices.append(device)
            }
            updateRadios(from: foundDevices + activePairedDevices())
            scanStatus = "Found \(radios.count) device(s)…"
        }
    }

    nonisolated func deviceInquiryComplete(_ sender: IOBluetoothDeviceInquiry!,
                                           error: IOReturn,
                                           aborted: Bool) {
        Task { @MainActor in
            isScanning = false
            // Merge scan results with already-paired devices
            let all = (foundDevices + activePairedDevices())
                .reduce(into: [String: IOBluetoothDevice]()) { dict, d in
                    if let addr = d.addressString { dict[addr] = d }
                }
                .values
            updateRadios(from: Array(all))
            scanStatus = radios.isEmpty ? "No TH-D75 devices found." :
                         "Found \(radios.count) device(s)."
        }
    }
}
