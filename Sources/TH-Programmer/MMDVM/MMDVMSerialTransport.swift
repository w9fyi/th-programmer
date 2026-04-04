// MMDVMSerialTransport.swift — POSIX serial transport for MMDVM devices

import Foundation
import Darwin

/// POSIX serial transport for communicating with MMDVM devices (TH-D75 in terminal mode).
/// 38400 baud, 8N1, raw mode — the TH-D75 uses 38400 (not 115200 like standard MMDVM modems).
final class MMDVMSerialTransport: MMDVMTransport, @unchecked Sendable {

    nonisolated deinit {}

    // MARK: - Callbacks

    var onStateChange: (@Sendable (MMDVMTransportState) -> Void)?
    var onDataReceived: (@Sendable (Data) -> Void)?

    // MARK: - Internal

    private let ioQueue = DispatchQueue(label: "com.th-programmer.mmdvm-serial", qos: .userInteractive)
    private var fileDescriptor: Int32?
    private var readSource: DispatchSourceRead?

    // MARK: - Open / Close

    func open(port: RadioSerialPort) throws {
        close()
        onStateChange?(.connecting(port.displayName))

        let descriptor = Darwin.open(port.path, O_RDWR | O_NOCTTY | O_NONBLOCK)
        guard descriptor >= 0 else {
            let err = String(cString: strerror(errno))
            onStateChange?(.error("Cannot open \(port.displayName): \(err)"))
            throw MMDVMTransportError.deviceUnavailable(port.path)
        }

        do {
            try configure(fileDescriptor: descriptor)
        } catch {
            Darwin.close(descriptor)
            throw error
        }

        fileDescriptor = descriptor
        installReadSource(for: descriptor, port: port)
        onStateChange?(.connected(port.displayName))
    }

    func close() {
        readSource?.cancel()
        readSource = nil

        if let descriptor = fileDescriptor {
            Darwin.close(descriptor)
            fileDescriptor = nil
        }

        onStateChange?(.disconnected)
    }

    // MARK: - DTR Control

    func setDTR(_ enabled: Bool) throws {
        guard let descriptor = fileDescriptor else {
            throw MMDVMTransportError.notOpen
        }
        let command = enabled ? TIOCSDTR : TIOCCDTR
        let result = ioctl(descriptor, UInt(command), 0)
        guard result == 0 else {
            throw MMDVMTransportError.ioctlFailed(errorString(prefix: "ioctl DTR"))
        }
    }

    // MARK: - Send

    func send(_ data: Data) throws {
        guard let descriptor = fileDescriptor else {
            throw MMDVMTransportError.notOpen
        }

        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.bindMemory(to: UInt8.self).baseAddress else {
                return
            }

            var bytesRemaining = data.count
            var offset = 0
            while bytesRemaining > 0 {
                let written = Darwin.write(descriptor, baseAddress.advanced(by: offset), bytesRemaining)
                if written > 0 {
                    bytesRemaining -= written
                    offset += written
                    continue
                }
                if written == -1 && errno == EINTR {
                    continue
                }
                throw MMDVMTransportError.writeFailed(errorString(prefix: "write"))
            }
        }
    }

    // MARK: - Serial Configuration

    private func configure(fileDescriptor: Int32) throws {
        var options = termios()
        guard tcgetattr(fileDescriptor, &options) == 0 else {
            throw MMDVMTransportError.configurationFailed(errorString(prefix: "tcgetattr"))
        }

        cfmakeraw(&options)
        options.c_cflag |= tcflag_t(CLOCAL | CREAD)
        options.c_cflag &= ~tcflag_t(PARENB)
        options.c_cflag &= ~tcflag_t(CSTOPB)
        options.c_cflag &= ~tcflag_t(CSIZE)
        options.c_cflag |= tcflag_t(CS8)

        // Set baud rate — 38400 for TH-D75 terminal mode (not 115200 like standard MMDVM)
        cfsetspeed(&options, speed_t(B38400))

        guard tcsetattr(fileDescriptor, TCSANOW, &options) == 0 else {
            throw MMDVMTransportError.configurationFailed(errorString(prefix: "tcsetattr"))
        }
    }

    /// Keep O_NONBLOCK active — the dispatch source read handler needs non-blocking I/O.
    /// Removed the previous setBlockingMode() which caused the read loop to hang.

    // MARK: - Read Source

    private func installReadSource(for descriptor: Int32, port: RadioSerialPort) {
        let source = DispatchSource.makeReadSource(fileDescriptor: descriptor, queue: ioQueue)
        source.setEventHandler { [weak self] in
            self?.readAvailableData(from: descriptor, port: port)
        }
        source.resume()
        readSource = source
    }

    private func readAvailableData(from descriptor: Int32, port: RadioSerialPort) {
        var buffer = [UInt8](repeating: 0, count: 4096)

        while true {
            let bytesRead = Darwin.read(descriptor, &buffer, buffer.count)
            if bytesRead > 0 {
                onDataReceived?(Data(buffer.prefix(bytesRead)))
                continue
            }

            if bytesRead == 0 {
                onStateChange?(.error("Serial device closed: \(port.displayName)"))
                close()
                return
            }

            if errno == EAGAIN || errno == EINTR {
                return
            }

            onStateChange?(.error(errorString(prefix: "read")))
            close()
            return
        }
    }

    // MARK: - Helpers

    private func errorString(prefix: String) -> String {
        let description = String(cString: strerror(errno))
        return "\(prefix): \(description)"
    }
}

// MARK: - Errors

enum MMDVMTransportError: Error, LocalizedError {
    case deviceUnavailable(String)
    case notOpen
    case configurationFailed(String)
    case writeFailed(String)
    case ioctlFailed(String)

    var errorDescription: String? {
        switch self {
        case .deviceUnavailable(let path):
            return "Cannot open serial device: \(path)"
        case .notOpen:
            return "Serial port is not open"
        case .configurationFailed(let detail):
            return "Serial configuration failed: \(detail)"
        case .writeFailed(let detail):
            return "Serial write failed: \(detail)"
        case .ioctlFailed(let detail):
            return "Serial ioctl failed: \(detail)"
        }
    }
}
