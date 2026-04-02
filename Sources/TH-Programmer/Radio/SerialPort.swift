// SerialPort.swift — IOKit/termios serial port for macOS
// Handles opening /dev/cu.usbmodem* devices with hardware flow control

import Foundation
import IOKit
import IOKit.serial

final class SerialPort {

    let path: String
    private var fd: Int32 = -1
    private var originalTermios = termios()

    var isOpen: Bool { fd >= 0 }

    init(path: String) {
        self.path = path
    }

    deinit {
        close()
    }

    // MARK: - Open / Close

    /// Open the port at the specified baud rate with optional hardware flow control and stop bits.
    func open(baudRate: Int32, hardwareFlowControl: Bool = true, twoStopBits: Bool = false) throws {
        fd = Darwin.open(path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard fd >= 0 else {
            throw SerialError.openFailed(path, errno)
        }

        // Exclusive access
        if ioctl(fd, TIOCEXCL) == -1 {
            Darwin.close(fd); fd = -1
            throw SerialError.ioctlFailed("TIOCEXCL", errno)
        }

        // Clear O_NONBLOCK — we want blocking I/O for the clone protocol
        guard fcntl(fd, F_SETFL, 0) != -1 else {
            Darwin.close(fd); fd = -1
            throw SerialError.ioctlFailed("F_SETFL", errno)
        }

        // Save original termios
        guard tcgetattr(fd, &originalTermios) == 0 else {
            Darwin.close(fd); fd = -1
            throw SerialError.termiosFailed("tcgetattr", errno)
        }

        try configure(baudRate: baudRate, hardwareFlowControl: hardwareFlowControl, twoStopBits: twoStopBits)
    }

    func close() {
        guard fd >= 0 else { return }
        tcsetattr(fd, TCSANOW, &originalTermios)
        Darwin.close(fd)
        fd = -1
    }

    // MARK: - Baud Rate Change

    func setBaudRate(_ baudRate: Int32, hardwareFlowControl: Bool = true, twoStopBits: Bool = false) throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        tcdrain(fd)  // flush pending output before switching baud rate
        try configure(baudRate: baudRate, hardwareFlowControl: hardwareFlowControl, twoStopBits: twoStopBits)
    }

    // MARK: - Read / Write

    func write(_ data: Data) throws {
        guard fd >= 0 else { throw SerialError.notOpen }
        try data.withUnsafeBytes { ptr in
            var written = 0
            while written < data.count {
                let n = Darwin.write(fd, ptr.baseAddress!.advanced(by: written), data.count - written)
                if n < 0 {
                    if errno == EAGAIN { continue }
                    throw SerialError.writeFailed(errno)
                }
                written += n
            }
        }
    }

    func write(_ byte: UInt8) throws {
        try write(Data([byte]))
    }

    /// Read exactly `count` bytes, blocking up to `timeout` seconds total.
    func read(count: Int, timeout: TimeInterval = 5.0) throws -> Data {
        guard fd >= 0 else { throw SerialError.notOpen }
        var buffer = Data(count: count)
        var received = 0
        let deadline = Date().addingTimeInterval(timeout)
        while received < count {
            if Date() > deadline {
                throw SerialError.timeout(received, count)
            }
            let n = buffer.withUnsafeMutableBytes { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress!.advanced(by: received), count - received)
            }
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(1000)
                    continue
                }
                throw SerialError.readFailed(errno)
            }
            if n == 0 { usleep(1000); continue }
            received += n
        }
        return buffer
    }

    /// Read up to `count` bytes within `timeout` seconds total.
    func readAvailable(maxCount: Int = 256, timeout: TimeInterval = 1.0) throws -> Data {
        guard fd >= 0 else { throw SerialError.notOpen }
        var buffer = Data(count: maxCount)
        let deadline = Date().addingTimeInterval(timeout)
        var received = 0
        while received < maxCount && Date() < deadline {
            let n = buffer.withUnsafeMutableBytes { ptr -> Int in
                Darwin.read(fd, ptr.baseAddress!.advanced(by: received), maxCount - received)
            }
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK {
                    usleep(5000)
                    continue
                }
                throw SerialError.readFailed(errno)
            }
            if n == 0 { break }
            received += n
        }
        return buffer.prefix(received)
    }

    /// Read one line (up to '\r' or '\n'), with timeout.
    func readLine(timeout: TimeInterval = 2.0) throws -> String {
        guard fd >= 0 else { throw SerialError.notOpen }
        var result = Data()
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            var byte: UInt8 = 0
            let n = Darwin.read(fd, &byte, 1)
            if n < 0 {
                if errno == EAGAIN || errno == EWOULDBLOCK { usleep(5000); continue }
                throw SerialError.readFailed(errno)
            }
            if n == 0 { usleep(5000); continue }
            if byte == 0x0D || byte == 0x0A { break }
            result.append(byte)
        }
        return String(data: result, encoding: .ascii) ?? ""
    }

    /// Discard any bytes waiting in the kernel receive buffer.
    /// Useful after opening a Bluetooth SPP port to flush connection
    /// preamble before sending the first CAT command.
    func flushInput() {
        guard fd >= 0 else { return }
        tcflush(fd, TCIFLUSH)
    }

    // MARK: - termios configuration

    private func configure(baudRate: Int32, hardwareFlowControl: Bool, twoStopBits: Bool = false) throws {
        var t = termios()
        tcgetattr(fd, &t)

        // Raw mode
        cfmakeraw(&t)

        // 8N1 or 8N2
        t.c_cflag &= ~UInt(PARENB | CSTOPB | CSIZE)
        t.c_cflag |= UInt(CS8 | CREAD | CLOCAL)
        if twoStopBits {
            t.c_cflag |= UInt(CSTOPB)
        }

        // Hardware flow control
        if hardwareFlowControl {
            t.c_cflag |= UInt(CRTSCTS)
        } else {
            t.c_cflag &= ~UInt(CRTSCTS)
        }

        // Baud rate (use iossiospeed for non-standard rates if needed)
        cfsetispeed(&t, speed_t(baudRate))
        cfsetospeed(&t, speed_t(baudRate))

        // Read timeouts: VMIN=0, VTIME=2 (200ms)
        // 200ms is enough to receive a full 135-byte block at 9600 baud (140ms),
        // and short enough that the 0x06 handshake reaches the radio within ~200ms
        // of the 0M echo — well inside the radio's clone-mode entry window.
        t.c_cc.16 = 0    // VMIN
        t.c_cc.17 = 2    // VTIME (tenths of a second)

        guard tcsetattr(fd, TCSANOW, &t) == 0 else {
            throw SerialError.termiosFailed("tcsetattr", errno)
        }

        // Flush pending output only — flushing input (TCIOFLUSH) would discard
        // bytes the radio just sent (e.g., the 57600-baud "ready" byte after
        // SET_LINE_CODING), so we intentionally leave the input buffer alone.
        tcflush(fd, TCOFLUSH)

        // When not using kernel-managed HFC, assert DTR and RTS manually.
        // For USB CDC ACM (TH-D75), the radio only responds after DTR=1 is received
        // via SET_CONTROL_LINE_STATE — without it the radio is completely silent.
        // Java/purejavacomm sets both; we must too.
        if !hardwareFlowControl {
            var flags: Int32 = TIOCM_DTR | TIOCM_RTS
            ioctl(fd, TIOCMBIS, &flags)
        }
    }

    // MARK: - Port Discovery

    /// Returns all available serial ports (cu.* devices).
    /// Order: usbmodem first (TH-D75 USB cable), then usbserial/SLAB, then Bluetooth, then rest.
    static func availablePorts() -> [String] {
        var ports: [String] = []
        let fm = FileManager.default
        guard let entries = try? fm.contentsOfDirectory(atPath: "/dev") else { return [] }
        for entry in entries.sorted() where entry.hasPrefix("cu.") {
            ports.append("/dev/\(entry)")
        }
        let usbmodem  = ports.filter { $0.contains("usbmodem") }
        let usbserial = ports.filter { !usbmodem.contains($0) &&
                                       ($0.contains("usbserial") || $0.contains("SLAB")) }
        let bluetooth = ports.filter { isBluetoothPort($0) }
        let rest      = ports.filter { !usbmodem.contains($0) && !usbserial.contains($0) &&
                                       !bluetooth.contains($0) }
        return usbmodem + usbserial + bluetooth + rest
    }

    /// True when the port path looks like a Bluetooth SPP virtual port rather than USB.
    static func isBluetoothPort(_ path: String) -> Bool {
        let name = URL(fileURLWithPath: path).lastPathComponent.lowercased()
        // Generic BT indicators
        if name.contains("bluetooth") || name.contains("-wireless") { return true }
        // TH-D75/D74 SPP ports appear as cu.TH-D75 or cu.TH-D75-SerialPort —
        // these are NOT "usbmodem" so anything non-usbmodem is treated as BT/serial
        return !name.contains("usbmodem")
    }
}

// MARK: - Errors

enum SerialError: Error, LocalizedError {
    case openFailed(String, Int32)
    case ioctlFailed(String, Int32)
    case termiosFailed(String, Int32)
    case notOpen
    case writeFailed(Int32)
    case readFailed(Int32)
    case timeout(Int, Int)

    var errorDescription: String? {
        switch self {
        case .openFailed(let path, let err):
            return "Failed to open \(path): errno \(err)"
        case .ioctlFailed(let op, let err):
            return "ioctl \(op) failed: errno \(err)"
        case .termiosFailed(let op, let err):
            return "termios \(op) failed: errno \(err)"
        case .notOpen:
            return "Serial port is not open"
        case .writeFailed(let err):
            return "Write failed: errno \(err)"
        case .readFailed(let err):
            return "Read failed: errno \(err)"
        case .timeout(let got, let want):
            return "Timeout: received \(got)/\(want) bytes"
        }
    }
}
