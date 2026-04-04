// RFCOMMTransport.swift — Direct IOBluetooth RFCOMM transport for TH-D75 MMDVM
//
// Bypasses the macOS virtual serial port (/dev/cu.*) and talks MMDVM frames
// directly on RFCOMM channel 2. Confirmed working by d75link binary analysis.

import Foundation
import IOBluetooth

/// Direct RFCOMM transport for MMDVM frame I/O with the TH-D75.
/// Uses IOBluetooth RFCOMM channel 2 — no virtual serial port intermediary.
final class RFCOMMTransport: NSObject, MMDVMTransport, IOBluetoothRFCOMMChannelDelegate, @unchecked Sendable {

    // MARK: - MMDVMTransport Callbacks

    var onStateChange: (@Sendable (MMDVMTransportState) -> Void)?
    var onDataReceived: (@Sendable (Data) -> Void)?

    // MARK: - Configuration

    /// Bluetooth MAC address of the TH-D75 (AA:BB:CC:DD:EE:FF format).
    let address: String

    /// RFCOMM channel ID — the TH-D75 uses channel 2 for MMDVM data.
    static let channelID: BluetoothRFCOMMChannelID = 2

    // MARK: - Internal State

    private let ioQueue = DispatchQueue(label: "com.th-programmer.rfcomm-transport", qos: .userInteractive)
    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var isOpen = false

    // MARK: - Init

    init(address: String) {
        self.address = address
        super.init()
    }

    /// Maximum connection attempts before giving up.
    static let maxConnectAttempts = 5

    /// Log file for connection diagnostics.
    private static let logPath = "/Users/justinmann/Desktop/rfcomm_connect.log"

    private func log(_ message: String) {
        let line = "\(ISO8601DateFormatter().string(from: Date())) \(message)\n"
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: Self.logPath) {
                if let handle = FileHandle(forWritingAtPath: Self.logPath) {
                    handle.seekToEndOfFile()
                    handle.write(data)
                    handle.closeFile()
                }
            } else {
                FileManager.default.createFile(atPath: Self.logPath, contents: data)
            }
        }
    }

    // MARK: - MMDVMTransport

    func open(port: RadioSerialPort) throws {
        // If already connected, don't reopen — a second open kills the working channel
        if isOpen && channel != nil {
            log("open() called but already connected — skipping")
            return
        }
        close()

        // Only clear log on first open, not reconnects
        if !FileManager.default.fileExists(atPath: Self.logPath) {
            try? "".write(toFile: Self.logPath, atomically: true, encoding: .utf8)
        }
        log("=== RFCOMM Connect Start ===")
        log("Address: \(address), channelID: \(Self.channelID)")

        guard let btDevice = IOBluetoothDevice(addressString: address) else {
            let msg = "Invalid Bluetooth address: \(address)"
            log("FATAL: \(msg)")
            onStateChange?(.error(msg))
            throw MMDVMTransportError.deviceUnavailable(msg)
        }

        log("Device name: \(btDevice.name ?? "nil"), paired: \(btDevice.isPaired())")

        device = btDevice
        onStateChange?(.connecting("RFCOMM \(address)"))

        // d75link pattern: retry the full ACL + RFCOMM sequence with backoff.
        // macOS Bluetooth is unreliable — first attempt after radio power-on often fails.
        var lastError = ""
        for attempt in 1...Self.maxConnectAttempts {
            if attempt > 1 {
                let delay = min(Double(1 << (attempt - 2)), 8.0)
                log("--- Retry \(attempt)/\(Self.maxConnectAttempts) after \(Int(delay))s delay ---")
                onStateChange?(.connecting("Retry \(attempt)/\(Self.maxConnectAttempts) in \(Int(delay))s…"))
                Thread.sleep(forTimeInterval: delay)
            }

            let isConn = btDevice.isConnected()
            log("Attempt \(attempt): isConnected=\(isConn), channel=\(channel != nil)")

            // Close stale baseband connection if device reports connected
            // but no RFCOMM channel is open (radio was power-cycled).
            if isConn && channel == nil {
                log("Attempt \(attempt): closing stale baseband")
                btDevice.closeConnection()
                Thread.sleep(forTimeInterval: 1.0)
                log("Attempt \(attempt): after closeConnection, isConnected=\(btDevice.isConnected())")
            }

            // Open ACL connection
            if !btDevice.isConnected() {
                log("Attempt \(attempt): opening ACL connection")
                let aclResult = btDevice.openConnection()
                log("Attempt \(attempt): openConnection result=0x\(String(format: "%08X", aclResult))")
                if aclResult != kIOReturnSuccess {
                    lastError = "ACL failed (0x\(String(format: "%08X", aclResult)))"
                    continue
                }
                log("Attempt \(attempt): waiting 2s for ACL handshake")
                Thread.sleep(forTimeInterval: 2.0)
                log("Attempt \(attempt): after wait, isConnected=\(btDevice.isConnected())")
            }

            // Open RFCOMM channel 2
            log("Attempt \(attempt): opening RFCOMM channel \(Self.channelID)")
            var rfcommChannel: IOBluetoothRFCOMMChannel?
            let openResult = btDevice.openRFCOMMChannelSync(
                &rfcommChannel,
                withChannelID: Self.channelID,
                delegate: self
            )

            log("Attempt \(attempt): openRFCOMMChannelSync result=0x\(String(format: "%08X", openResult)), channel=\(rfcommChannel != nil)")

            if openResult == kIOReturnSuccess, let rfcommChannel {
                channel = rfcommChannel
                isOpen = true
                log("SUCCESS: RFCOMM channel \(Self.channelID) open")
                onStateChange?(.connected("RFCOMM ch\(Self.channelID) \(address)"))
                return
            }

            if openResult == IOReturn(kIOReturnNotPermitted) {
                lastError = "Bluetooth permission required — check macOS prompt"
                log("Attempt \(attempt): NotPermitted — waiting 2s for TCC prompt")
                Thread.sleep(forTimeInterval: 2.0)
            } else {
                lastError = "RFCOMM ch\(Self.channelID) failed (0x\(String(format: "%08X", openResult)))"
            }
            log("Attempt \(attempt): \(lastError)")
        }

        // All attempts exhausted
        let msg = "Could not connect after \(Self.maxConnectAttempts) attempts: \(lastError)"
        log("FAILED: \(msg)")
        onStateChange?(.error(msg))
        throw MMDVMTransportError.deviceUnavailable(msg)
    }

    func close() {
        log("close() called, isOpen=\(isOpen), channel=\(channel != nil)")
        // Log call stack to trace who's calling close
        let trace = Thread.callStackSymbols.prefix(6).joined(separator: "\n  ")
        log("close() stack:\n  \(trace)")

        guard isOpen else { return }
        isOpen = false

        if let ch = channel {
            _ = ch.close()
            ch.setDelegate(nil)
        }
        channel = nil

        // Don't close the ACL connection — other services (audio, etc.) may use it.
        // macOS will close it automatically when no channels remain.
        device = nil

        onStateChange?(.disconnected)
    }

    func send(_ data: Data) throws {
        guard let channel, isOpen else {
            throw MMDVMTransportError.notOpen
        }

        // writeAsync expects a mutable pointer
        var mutableData = data
        let result = mutableData.withUnsafeMutableBytes { rawBuffer -> IOReturn in
            guard let baseAddress = rawBuffer.baseAddress else {
                return IOReturn(kIOReturnBadArgument)
            }
            return channel.writeAsync(
                baseAddress.assumingMemoryBound(to: UInt8.self),
                length: UInt16(data.count),
                refcon: nil
            )
        }

        if result != kIOReturnSuccess {
            throw MMDVMTransportError.writeFailed("RFCOMM write failed (0x\(String(format: "%08X", result)))")
        }
    }

    func setDTR(_ enabled: Bool) throws {
        // DTR is not applicable to RFCOMM — no-op.
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelData(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        data dataPointer: UnsafeMutableRawPointer!,
        length dataLength: Int
    ) {
        guard let dataPointer, dataLength > 0 else { return }
        let data = Data(bytes: dataPointer, count: dataLength)
        onDataReceived?(data)
    }

    func rfcommChannelOpenComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        status error: IOReturn
    ) {
        if error != kIOReturnSuccess {
            isOpen = false
            onStateChange?(.error("RFCOMM open complete with error 0x\(String(format: "%08X", error))"))
        }
    }

    func rfcommChannelClosed(_ rfcommChannel: IOBluetoothRFCOMMChannel!) {
        let wasOpen = isOpen
        isOpen = false
        channel = nil

        if wasOpen {
            onStateChange?(.error("RFCOMM channel closed unexpectedly"))
        } else {
            onStateChange?(.disconnected)
        }
    }

    func rfcommChannelWriteComplete(
        _ rfcommChannel: IOBluetoothRFCOMMChannel!,
        refcon: UnsafeMutableRawPointer!,
        status error: IOReturn
    ) {
        // Fire-and-forget — voice frames are time-sensitive, no retry.
        if error != kIOReturnSuccess {
            onStateChange?(.error("RFCOMM write error 0x\(String(format: "%08X", error))"))
        }
    }

    // MARK: - Synthetic Port

    /// Create a synthetic RadioSerialPort for this RFCOMM connection.
    /// Used by MMDVMBridge's reconnect logic which stores `lastPort`.
    var syntheticPort: RadioSerialPort {
        RadioSerialPort(
            path: "rfcomm://\(address)",
            displayName: "Direct RFCOMM — \(address)",
            transportKind: .bluetoothSPP,
            score: 300  // highest priority
        )
    }
}
