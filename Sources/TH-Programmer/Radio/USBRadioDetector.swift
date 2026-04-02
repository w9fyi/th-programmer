// USBRadioDetector.swift — IOKit serial-port watcher + TH-D74/D75 ID probe

import Foundation
import IOKit
import IOKit.serial

/// Watches for new USB serial ports via IOKit notifications and probes each
/// new `usbmodem` device with the CAT `ID` command to confirm it's a TH-D74
/// or TH-D75. Callbacks fire on the main thread.
final class USBRadioDetector {

    struct DetectedRadio: Equatable {
        let port: String
        let model: String   // "TH-D74" or "TH-D75"
    }

    /// Called on the main thread when a matching radio is confirmed.
    var onDetected: ((DetectedRadio) -> Void)?
    /// Called on the main thread when any USB serial port disappears
    /// (caller should re-scan available ports).
    var onRemoved: (() -> Void)?

    private var notificationPort: IONotificationPortRef?
    private var addedIterator:   io_iterator_t = 0
    private var removedIterator: io_iterator_t = 0

    deinit { stop() }

    // MARK: - Start / Stop

    func start() {
        guard notificationPort == nil else { return }
        notificationPort = IONotificationPortCreate(kIOMainPortDefault)
        guard let np = notificationPort else { return }

        let src = IONotificationPortGetRunLoopSource(np).takeUnretainedValue()
        CFRunLoopAddSource(CFRunLoopGetMain(), src, .defaultMode)

        let ctx = Unmanaged.passUnretained(self).toOpaque()

        // ── Appeared ──────────────────────────────────────────────────────────
        let addMatch = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        addMatch[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        IOServiceAddMatchingNotification(
            np, kIOFirstMatchNotification, addMatch as CFDictionary,
            { ctx, iter in
                guard let ctx else { return }
                Unmanaged<USBRadioDetector>.fromOpaque(ctx)
                    .takeUnretainedValue().handleAdded(iter)
            },
            ctx, &addedIterator
        )
        // Drain devices already present at launch — arms the notification
        // without probing ports the user already sees in the picker.
        drainIterator(addedIterator, probe: false)

        // ── Disappeared ───────────────────────────────────────────────────────
        let removeMatch = IOServiceMatching(kIOSerialBSDServiceValue) as NSMutableDictionary
        removeMatch[kIOSerialBSDTypeKey] = kIOSerialBSDAllTypes
        IOServiceAddMatchingNotification(
            np, kIOTerminatedNotification, removeMatch as CFDictionary,
            { ctx, iter in
                guard let ctx else { return }
                Unmanaged<USBRadioDetector>.fromOpaque(ctx)
                    .takeUnretainedValue().handleRemoved(iter)
            },
            ctx, &removedIterator
        )
        drainIterator(removedIterator, probe: false)
    }

    func stop() {
        if addedIterator   != 0 { IOObjectRelease(addedIterator);   addedIterator   = 0 }
        if removedIterator != 0 { IOObjectRelease(removedIterator); removedIterator = 0 }
        if let np = notificationPort {
            IONotificationPortDestroy(np)
            notificationPort = nil
        }
    }

    // MARK: - IOKit callbacks

    private func handleAdded(_ iterator: io_iterator_t) {
        drainIterator(iterator, probe: true)
    }

    private func handleRemoved(_ iterator: io_iterator_t) {
        var service = IOIteratorNext(iterator)
        var didRemove = false
        while service != 0 {
            didRemove = true
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
        if didRemove {
            DispatchQueue.main.async { self.onRemoved?() }
        }
    }

    private func drainIterator(_ iterator: io_iterator_t, probe: Bool) {
        var service = IOIteratorNext(iterator)
        while service != 0 {
            if probe,
               let path = calloutPath(from: service),
               path.contains("usbmodem"),
               isKenwoodRadio(service) {
                probePort(path)
            }
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }

    // MARK: - IOKit helpers

    private func calloutPath(from service: io_object_t) -> String? {
        guard let val = IORegistryEntryCreateCFProperty(
            service, kIOCalloutDeviceKey as CFString, kCFAllocatorDefault, 0
        ) else { return nil }
        return val.takeRetainedValue() as? String
    }

    /// Returns true only if the IOKit service's USB product name contains
    /// a Kenwood TH-D74 or TH-D75 identifier. Searches up the parent chain
    /// so we never open a port that belongs to a different USB device.
    private func isKenwoodRadio(_ service: io_object_t) -> Bool {
        guard let val = IORegistryEntrySearchCFProperty(
            service, kIOServicePlane,
            "USB Product Name" as CFString,
            kCFAllocatorDefault,
            IOOptionBits(kIORegistryIterateParents | kIORegistryIterateRecursively)
        ) else { return false }
        let name = (val as? String)?.lowercased() ?? ""
        return name.contains("th-d74") || name.contains("th-d75")
            || name.contains("thd74") || name.contains("thd75")
    }

    // MARK: - ID probe

    /// Opens the port briefly, sends `ID\r`, and reports the model if the
    /// response contains "TH-D74" or "TH-D75". Runs on a background queue.
    private func probePort(_ path: String) {
        DispatchQueue.global(qos: .utility).async { [weak self] in
            // Let the port settle — macOS registers the device before it's ready
            usleep(600_000)

            let fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
            guard fd >= 0 else { return }
            defer { Darwin.close(fd) }

            // Switch to blocking I/O
            _ = fcntl(fd, F_SETFL, 0)

            // 9600 8N1, no hardware flow control (matches live CAT mode)
            var t = termios()
            tcgetattr(fd, &t)
            cfmakeraw(&t)
            t.c_cflag &= ~UInt(PARENB | CSTOPB | CSIZE | CRTSCTS)
            t.c_cflag |=  UInt(CS8 | CREAD | CLOCAL)
            cfsetispeed(&t, speed_t(B9600))
            cfsetospeed(&t, speed_t(B9600))
            t.c_cc.16 = 0    // VMIN  — return as soon as any data arrives
            t.c_cc.17 = 15   // VTIME — 1.5 s inter-byte timeout
            tcsetattr(fd, TCSAFLUSH, &t)

            // Assert DTR + RTS — required; the radio stays silent without them
            var modemBits: Int32 = TIOCM_DTR | TIOCM_RTS
            ioctl(fd, TIOCMBIS, &modemBits)
            usleep(150_000)

            // Send ID query
            Darwin.write(fd, "ID\r", 3)

            // Read until \r or 2-second deadline
            var responseBuf = Data()
            let deadline = Date().addingTimeInterval(2.0)
            while responseBuf.count < 32 && Date() < deadline {
                var byte: UInt8 = 0
                let n = Darwin.read(fd, &byte, 1)
                if n > 0 {
                    if byte == 0x0D { break }
                    responseBuf.append(byte)
                } else {
                    usleep(10_000)
                }
            }

            let response = String(data: responseBuf, encoding: .ascii) ?? ""
            let model: String?
            if      response.contains("TH-D75") { model = "TH-D75" }
            else if response.contains("TH-D74") { model = "TH-D74" }
            else                                { model = nil }

            if let model {
                let detected = DetectedRadio(port: path, model: model)
                DispatchQueue.main.async { self?.onDetected?(detected) }
            }
        }
    }
}
