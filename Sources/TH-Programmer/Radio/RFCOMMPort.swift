// RFCOMMPort.swift — Direct IOBluetooth RFCOMM transport for CAT commands
//
// Direct port of thd75 reference library's bluetooth_mac.m to Swift.
// Uses pipe()-based I/O and a run loop pump thread — proven architecture.

import Foundation
import IOBluetooth

final class RFCOMMPort: NSObject, RadioPort, IOBluetoothRFCOMMChannelDelegate {

    /// Device name to find in pairedDevices() (e.g. "TH-D75").
    private let deviceName: String

    /// RFCOMM channel ID (SPP = 2 for TH-D75, confirmed by reference lib).
    private let rfcommChannelID: BluetoothRFCOMMChannelID

    private var device: IOBluetoothDevice?
    private var channel: IOBluetoothRFCOMMChannel?
    private var isOpenFlag = false

    // Pipe: delegate writes to pipeWrite, caller reads from pipeRead.
    private var pipeRead: Int32 = -1
    private var pipeWrite: Int32 = -1

    // Run loop pump — wakes main run loop so IOBluetooth callbacks fire.
    private static var pumpThread: Thread?
    private static var pumpRunning = false
    private static let pumpLock = NSLock()
    private static var openCount = 0

    init(deviceName: String, rfcommChannel: BluetoothRFCOMMChannelID = 2) {
        self.deviceName = deviceName
        self.rfcommChannelID = rfcommChannel
        super.init()
    }

    /// Convenience: create from a Bluetooth address by looking up the name.
    /// Falls back to "TH-D75" if the address doesn't match a paired device.
    convenience init(address: String) {
        // Find the device name from paired devices matching this address
        let name: String
        if let devices = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice],
           let match = devices.first(where: {
               $0.addressString?.replacingOccurrences(of: ":", with: "-").lowercased()
                   == address.lowercased()
               || $0.addressString?.lowercased() == address.lowercased()
           }) {
            name = match.name ?? "TH-D75"
        } else {
            name = "TH-D75"
        }
        self.init(deviceName: name)
    }

    // MARK: - RadioPort

    func open(baudRate: Int32, hardwareFlowControl: Bool, twoStopBits: Bool) throws {
        guard !isOpenFlag else { return }

        var openError: Error?
        if Thread.isMainThread {
            openError = doOpen()
        } else {
            let sem = DispatchSemaphore(value: 0)
            DispatchQueue.main.async {
                openError = self.doOpen()
                sem.signal()
            }
            sem.wait()
        }
        if let openError { throw openError }
    }

    /// Direct translation of bluetooth_mac.m do_rfcomm_open().
    /// MUST run on main thread (CFRunLoop).
    private func doOpen() -> Error? {
        print("[RFCOMMPort] doOpen name=\(deviceName) ch=\(rfcommChannelID) isMainThread=\(Thread.isMainThread)")

        // Start pump BEFORE anything else — bluetooth_mac.m:135-138
        // The pump thread must be running during SDP and RFCOMM open,
        // not just after. IOBluetooth's internal state machine needs
        // continuous run loop wake-ups to process callbacks.
        Self.startPump()

        // 1. Create pipe
        var fds: [Int32] = [0, 0]
        guard pipe(&fds) == 0 else {
            return SerialError.openFailed("pipe() failed", errno)
        }
        pipeRead = fds[0]
        pipeWrite = fds[1]
        fcntl(pipeRead, F_SETFL, fcntl(pipeRead, F_GETFL) | O_NONBLOCK)

        // 2. Find device by name from pairedDevices() — NOT IOBluetoothDevice(addressString:)
        //    The address-based constructor creates a proxy that lacks full stack integration.
        //    pairedDevices() returns the real managed device objects.
        guard let allPaired = IOBluetoothDevice.pairedDevices() as? [IOBluetoothDevice] else {
            print("[RFCOMMPort] pairedDevices() returned nil")
            closePipe(); Self.stopPump()
            return SerialError.openFailed("No paired Bluetooth devices", -1)
        }

        let names = allPaired.map { $0.name ?? "(nil)" }
        print("[RFCOMMPort] paired devices: \(names)")

        guard let btDevice = allPaired.first(where: { $0.name == deviceName }) else {
            print("[RFCOMMPort] device '\(deviceName)' not found in paired devices")
            closePipe(); Self.stopPump()
            return SerialError.openFailed("Device '\(deviceName)' not found in paired devices", -1)
        }
        device = btDevice
        print("[RFCOMMPort] found device: name=\(btDevice.name ?? "nil") connected=\(btDevice.isConnected())")

        // 3. Connect if needed
        if !btDevice.isConnected() {
            print("[RFCOMMPort] opening ACL connection")
            let aclResult = btDevice.openConnection()
            print("[RFCOMMPort] openConnection result=0x\(String(format: "%08X", aclResult))")
            if aclResult != kIOReturnSuccess {
                closePipe(); Self.stopPump()
                return SerialError.openFailed("ACL connection failed", -1)
            }
            // Wait for ACL to complete
            for i in 0..<40 {
                if btDevice.isConnected() { break }
                if i % 10 == 0 { print("[RFCOMMPort] waiting for ACL... \(i*50)ms") }
                CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }
            print("[RFCOMMPort] after ACL: connected=\(btDevice.isConnected())")
        }

        guard btDevice.isConnected() else {
            closePipe(); Self.stopPump()
            return SerialError.openFailed("Device did not connect", -1)
        }

        // 4. Open RFCOMM channel — try sync first, then async fallback
        var rfcomm: IOBluetoothRFCOMMChannel?

        // Attempt 1: openRFCOMMChannelSync — handles run loop internally
        print("[RFCOMMPort] trying openRFCOMMChannelSync ch=\(rfcommChannelID)")
        let syncResult = btDevice.openRFCOMMChannelSync(
            &rfcomm,
            withChannelID: rfcommChannelID,
            delegate: self
        )
        print("[RFCOMMPort] sync result=0x\(String(format: "%08X", syncResult)) channel=\(rfcomm != nil)")

        if syncResult == kIOReturnSuccess, let rfcomm {
            channel = rfcomm
            isOpenFlag = true
            print("[RFCOMMPort] RFCOMM open SUCCESS (sync)")
        } else {
            // Attempt 2: close stale, SDP reconnect, async open
            print("[RFCOMMPort] sync failed — trying SDP reconnect + async")
            rfcomm = nil

            btDevice.closeConnection()
            for i in 0..<60 {
                if !btDevice.isConnected() { break }
                usleep(50_000)
            }

            btDevice.performSDPQuery(nil)
            for i in 0..<100 {
                if btDevice.isConnected() { break }
                CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }

            guard btDevice.isConnected() else {
                closePipe(); Self.stopPump()
                return SerialError.openFailed("Device did not reconnect after SDP", -1)
            }

            let asyncResult = btDevice.openRFCOMMChannelAsync(
                &rfcomm,
                withChannelID: rfcommChannelID,
                delegate: self
            )
            print("[RFCOMMPort] async result=0x\(String(format: "%08X", asyncResult))")

            guard asyncResult == kIOReturnSuccess else {
                closePipe(); Self.stopPump()
                return SerialError.openFailed("RFCOMM async open failed", -1)
            }

            for i in 0..<200 {
                if isOpenFlag { break }
                if i % 40 == 0 { print("[RFCOMMPort] waiting... \(i*50)ms") }
                CFRunLoopRunInMode(.defaultMode, 0.05, false)
            }

            guard isOpenFlag else {
                if let ch = rfcomm { ch.setDelegate(nil); ch.close() }
                closePipe(); Self.stopPump()
                return SerialError.openFailed("RFCOMM channel did not open within 10s", -1)
            }
            channel = rfcomm
            print("[RFCOMMPort] RFCOMM open SUCCESS (async)")
        }
        return nil
    }

    func write(_ data: Data) throws {
        guard let channel, isOpenFlag else { throw SerialError.notOpen }
        let hex = data.prefix(32).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[RFCOMMPort] write \(data.count)B: \(hex)")
        // writeSync — same as bluetooth_mac.m:161
        var mutableData = data
        let result = mutableData.withUnsafeMutableBytes { raw -> IOReturn in
            guard let base = raw.baseAddress else { return IOReturn(kIOReturnBadArgument) }
            return channel.writeSync(base.assumingMemoryBound(to: UInt8.self),
                                     length: UInt16(data.count))
        }
        if result != kIOReturnSuccess {
            print("[RFCOMMPort] writeSync FAILED 0x\(String(format: "%08X", result))")
            throw SerialError.writeFailed(Int32(result))
        }
    }

    func read(count: Int, timeout: TimeInterval) throws -> Data {
        guard pipeRead >= 0 else { throw SerialError.notOpen }
        var buf = Data(count: count)
        var received = 0
        let deadline = Date().addingTimeInterval(timeout)
        while received < count {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { throw SerialError.timeout(received, count) }
            var pfd = pollfd(fd: pipeRead, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, Int32(min(remaining * 1000, 500)))
            if pr < 0 { if errno == EINTR { continue }; throw SerialError.readFailed(errno) }
            if pr == 0 { continue }
            if pfd.revents & Int16(POLLHUP | POLLERR) != 0 { throw SerialError.notOpen }
            let n = buf.withUnsafeMutableBytes { ptr -> Int in
                Darwin.read(pipeRead, ptr.baseAddress!.advanced(by: received), count - received)
            }
            if n < 0 { if errno == EAGAIN { continue }; throw SerialError.readFailed(errno) }
            if n == 0 { continue }
            received += n
        }
        return buf
    }

    func readAvailable(maxCount: Int, timeout: TimeInterval) throws -> Data {
        guard pipeRead >= 0 else { throw SerialError.notOpen }
        var buf = Data(count: maxCount)
        var received = 0
        let deadline = Date().addingTimeInterval(timeout)
        while received < maxCount {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var pfd = pollfd(fd: pipeRead, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, Int32(min(remaining * 1000, 500)))
            if pr <= 0 { break }
            if pfd.revents & Int16(POLLHUP | POLLERR) != 0 { break }
            let n = buf.withUnsafeMutableBytes { ptr -> Int in
                Darwin.read(pipeRead, ptr.baseAddress!.advanced(by: received), maxCount - received)
            }
            if n <= 0 { break }
            received += n
        }
        return buf.prefix(received)
    }

    func readLine(timeout: TimeInterval) throws -> String {
        guard pipeRead >= 0 else { throw SerialError.notOpen }
        var result = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            if remaining <= 0 { break }
            var pfd = pollfd(fd: pipeRead, events: Int16(POLLIN), revents: 0)
            let pr = poll(&pfd, 1, Int32(min(remaining * 1000, 500)))
            if pr < 0 { if errno == EINTR { continue }; throw SerialError.readFailed(errno) }
            if pr == 0 { continue }
            if pfd.revents & Int16(POLLHUP | POLLERR) != 0 { break }
            var byte: UInt8 = 0
            let n = Darwin.read(pipeRead, &byte, 1)
            if n <= 0 { continue }
            if byte == 0x0D || byte == 0x0A { break }
            result.append(byte)
        }
        return String(data: result, encoding: .ascii) ?? ""
    }

    func flushInput() {
        guard pipeRead >= 0 else { return }
        var trash = [UInt8](repeating: 0, count: 1024)
        while Darwin.read(pipeRead, &trash, trash.count) > 0 {}
    }

    func close() {
        guard isOpenFlag else { return }
        isOpenFlag = false
        // Nil delegate FIRST to prevent use-after-free (bluetooth_mac.m:182)
        if let ch = channel {
            ch.setDelegate(nil)
            ch.close()
        }
        channel = nil
        device = nil
        closePipe()
        Self.stopPump()
    }

    func isHealthy() -> Bool { isOpenFlag && channel != nil && pipeRead >= 0 }

    func setBaudRate(_ rate: Int32, hardwareFlowControl: Bool, twoStopBits: Bool) throws {}

    // MARK: - Pipe

    private func closePipe() {
        if pipeWrite >= 0 { Darwin.close(pipeWrite); pipeWrite = -1 }
        if pipeRead >= 0 { Darwin.close(pipeRead); pipeRead = -1 }
    }

    // MARK: - Run loop pump (bluetooth_mac.m:41-48)

    private static func startPump() {
        pumpLock.lock()
        defer { pumpLock.unlock() }
        openCount += 1
        guard pumpThread == nil else { return }
        pumpRunning = true
        let t = Thread {
            while Self.pumpRunning {
                CFRunLoopWakeUp(CFRunLoopGetMain())
                usleep(10_000)
            }
        }
        t.name = "RFCOMMPort-RunLoopPump"
        t.qualityOfService = .userInteractive
        t.start()
        pumpThread = t
    }

    private static func stopPump() {
        pumpLock.lock()
        openCount -= 1
        if openCount <= 0 { openCount = 0; pumpRunning = false; pumpThread = nil }
        pumpLock.unlock()
    }

    // MARK: - IOBluetoothRFCOMMChannelDelegate

    func rfcommChannelOpenComplete(_ ch: IOBluetoothRFCOMMChannel!, status error: IOReturn) {
        print("[RFCOMMPort] openComplete status=0x\(String(format: "%08X", error))")
        if error == kIOReturnSuccess { isOpenFlag = true }
    }

    // bluetooth_mac.m:28-29 — write received data into pipe
    func rfcommChannelData(_ ch: IOBluetoothRFCOMMChannel!,
                           data ptr: UnsafeMutableRawPointer!, length len: Int) {
        guard let ptr, len > 0, pipeWrite >= 0 else { return }
        let hex = Data(bytes: ptr, count: min(len, 32)).map { String(format: "%02X", $0) }.joined(separator: " ")
        print("[RFCOMMPort] data \(len)B: \(hex)")
        _ = Darwin.write(pipeWrite, ptr, len)
    }

    func rfcommChannelClosed(_ ch: IOBluetoothRFCOMMChannel!) {
        print("[RFCOMMPort] channelClosed")
        isOpenFlag = false; channel = nil; closePipe()
    }

    func rfcommChannelWriteComplete(_ ch: IOBluetoothRFCOMMChannel!,
                                     refcon: UnsafeMutableRawPointer!, status: IOReturn) {}
}
