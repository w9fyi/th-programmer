// PosixUDPSocket.swift — POSIX UDP socket wrapper for D-STAR reflector connections
//
// NWConnection (Network.framework) fails silently on macOS 26 for ad-hoc signed apps.
// This uses raw POSIX sockets (socket/sendto/recvfrom) which work reliably.

import Foundation

/// Thin wrapper around a POSIX UDP socket with async receive via DispatchSource.
final class PosixUDPSocket: @unchecked Sendable {

    nonisolated deinit {}

    private var fd: Int32 = -1
    private var remoteAddr: sockaddr_in?
    private var readSource: DispatchSourceRead?
    private let queue: DispatchQueue

    /// Called when data is received.
    var onReceive: ((Data) -> Void)?

    /// Called on error.
    var onError: ((String) -> Void)?

    init(queue: DispatchQueue) {
        self.queue = queue
    }

    // MARK: - Connect

    /// Create a UDP socket and resolve the remote host.
    /// - Parameters:
    ///   - host: Remote hostname or IP.
    ///   - port: Remote port.
    ///   - localPort: Local port to bind to (0 = ephemeral). DExtra requires 30001.
    /// Returns true on success.
    func open(host: String, port: UInt16, localPort: UInt16 = 0) -> Bool {
        // Resolve hostname
        guard let addr = resolveHost(host, port: port) else {
            onError?("DNS resolution failed for \(host)")
            return false
        }
        remoteAddr = addr

        // Create UDP socket
        fd = socket(AF_INET, SOCK_DGRAM, IPPROTO_UDP)
        guard fd >= 0 else {
            onError?("socket() failed: \(String(cString: strerror(errno)))")
            return false
        }

        // Allow address reuse (needed when binding to a fixed port)
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int32>.size))

        // Bind to local port if specified
        if localPort > 0 {
            var bindAddr = sockaddr_in()
            bindAddr.sin_family = sa_family_t(AF_INET)
            bindAddr.sin_port = localPort.bigEndian
            bindAddr.sin_addr.s_addr = INADDR_ANY.bigEndian
            let bindResult = withUnsafePointer(to: &bindAddr) { ptr in
                ptr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    bind(fd, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult < 0 {
                onError?("bind() to port \(localPort) failed: \(String(cString: strerror(errno)))")
                Darwin.close(fd)
                fd = -1
                return false
            }
        }

        // Set non-blocking for the dispatch source
        var flags = fcntl(fd, F_GETFL)
        flags |= O_NONBLOCK
        fcntl(fd, F_SETFL, flags)

        return true
    }

    // MARK: - Send

    /// Send data to the remote host.
    func send(_ data: Data) -> Bool {
        guard fd >= 0, var addr = remoteAddr else { return false }

        let result = data.withUnsafeBytes { ptr -> Int in
            withUnsafePointer(to: &addr) { addrPtr in
                addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                    sendto(fd, ptr.baseAddress, data.count, 0, sa, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }

        if result < 0 {
            onError?("sendto() failed: \(String(cString: strerror(errno)))")
            return false
        }
        return true
    }

    // MARK: - Receive

    /// Start async receive loop using DispatchSource.
    func startReceiving() {
        guard fd >= 0 else { return }
        stopReceiving()

        let source = DispatchSource.makeReadSource(fileDescriptor: fd, queue: queue)
        source.setEventHandler { [weak self] in
            self?.handleReadEvent()
        }
        source.setCancelHandler { [weak self] in
            // Don't close fd here — close() handles that
            self?.readSource = nil
        }
        readSource = source
        source.resume()
    }

    /// Stop the receive loop.
    func stopReceiving() {
        readSource?.cancel()
        readSource = nil
    }

    private func handleReadEvent() {
        guard fd >= 0 else { return }

        var buffer = [UInt8](repeating: 0, count: 2048)
        var senderAddr = sockaddr_in()
        var addrLen = socklen_t(MemoryLayout<sockaddr_in>.size)

        let bytesRead = withUnsafeMutablePointer(to: &senderAddr) { addrPtr in
            addrPtr.withMemoryRebound(to: sockaddr.self, capacity: 1) { sa in
                recvfrom(fd, &buffer, buffer.count, 0, sa, &addrLen)
            }
        }

        if bytesRead > 0 {
            let data = Data(buffer[0..<bytesRead])
            // Log non-keepalive packets to diagnostic file for debugging
            let isKeepalive = data.count == 3 && data[data.startIndex] == 0x03
            if !isKeepalive {
                let hex = data.prefix(20).map { String(format: "%02X", $0) }.joined(separator: " ")
                let line = "\(ISO8601DateFormatter().string(from: Date())) UDP RAW RX: \(data.count)b [\(hex)]\n"
                if let logData = line.data(using: .utf8),
                   let h = FileHandle(forWritingAtPath: "/Users/justinmann/Desktop/rfcomm_connect.log") {
                    h.seekToEndOfFile(); h.write(logData); h.closeFile()
                }
            }
            onReceive?(data)
        }
    }

    // MARK: - Close

    func close() {
        stopReceiving()
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
        remoteAddr = nil
    }

    var isOpen: Bool { fd >= 0 }

    // MARK: - DNS Resolution

    private func resolveHost(_ host: String, port: UInt16) -> sockaddr_in? {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_DGRAM
        hints.ai_protocol = IPPROTO_UDP

        var result: UnsafeMutablePointer<addrinfo>?
        let portStr = String(port)
        let status = getaddrinfo(host, portStr, &hints, &result)
        guard status == 0, let addrInfo = result else {
            if let result { freeaddrinfo(result) }
            return nil
        }
        defer { freeaddrinfo(result!) }

        guard addrInfo.pointee.ai_family == AF_INET,
              addrInfo.pointee.ai_addrlen == MemoryLayout<sockaddr_in>.size else {
            return nil
        }

        var addr = sockaddr_in()
        memcpy(&addr, addrInfo.pointee.ai_addr, Int(addrInfo.pointee.ai_addrlen))
        return addr
    }
}

// MARK: - PosixTCPSocket

/// Simple synchronous TCP socket for one-shot operations (like DPlus auth).
/// Runs on a background queue — do NOT use on the main thread.
final class PosixTCPSocket: @unchecked Sendable {

    nonisolated deinit {}

    private var fd: Int32 = -1

    /// Connect to a TCP server. Tries all resolved IPs until one connects.
    /// Blocks until connected or all addresses exhausted.
    func connect(host: String, port: UInt16, timeout: TimeInterval = 10.0) -> Bool {
        // Resolve — may return multiple IPs (round-robin DNS)
        var hints = addrinfo()
        hints.ai_family = AF_INET
        hints.ai_socktype = SOCK_STREAM
        hints.ai_protocol = IPPROTO_TCP

        var result: UnsafeMutablePointer<addrinfo>?
        let status = getaddrinfo(host, String(port), &hints, &result)
        guard status == 0, let firstAddr = result else {
            if let result { freeaddrinfo(result) }
            return false
        }
        defer { freeaddrinfo(firstAddr) }

        // Try each resolved address — auth.dstargateway.org has multiple IPs
        // and some are unreachable, so we must try them all.
        let perAddrTimeout = max(timeout / 3, 3.0)  // split timeout across attempts
        var current: UnsafeMutablePointer<addrinfo>? = firstAddr
        while let addrInfo = current {
            if tryConnect(addrInfo: addrInfo, timeout: perAddrTimeout) {
                return true
            }
            current = addrInfo.pointee.ai_next
        }

        return false
    }

    /// Attempt a single TCP connect to one address with timeout.
    private func tryConnect(addrInfo: UnsafeMutablePointer<addrinfo>, timeout: TimeInterval) -> Bool {
        // Create socket
        fd = socket(AF_INET, SOCK_STREAM, IPPROTO_TCP)
        guard fd >= 0 else { return false }

        // Set non-blocking for connect with timeout
        var flags = fcntl(fd, F_GETFL)
        fcntl(fd, F_SETFL, flags | O_NONBLOCK)

        // Initiate connect
        let connectResult = Darwin.connect(fd, addrInfo.pointee.ai_addr, addrInfo.pointee.ai_addrlen)
        if connectResult < 0 && errno != EINPROGRESS {
            Darwin.close(fd)
            fd = -1
            return false
        }

        // Wait for connect with select()
        var writeSet = fd_set()
        withUnsafeMutablePointer(to: &writeSet) { ptr in
            __darwin_fd_zero(ptr)
            __darwin_fd_set(fd, ptr)
        }
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        let selectResult = select(fd + 1, nil, &writeSet, nil, &tv)

        if selectResult <= 0 {
            Darwin.close(fd)
            fd = -1
            return false
        }

        // Check for connect error
        var optError: Int32 = 0
        var optLen = socklen_t(MemoryLayout<Int32>.size)
        getsockopt(fd, SOL_SOCKET, SO_ERROR, &optError, &optLen)
        if optError != 0 {
            Darwin.close(fd)
            fd = -1
            return false
        }

        // Restore blocking mode for send/recv
        flags = fcntl(fd, F_GETFL)
        fcntl(fd, F_SETFL, flags & ~O_NONBLOCK)

        return true
    }

    /// Send all data. Blocks until complete.
    func sendAll(_ data: Data) -> Bool {
        guard fd >= 0 else { return false }
        return data.withUnsafeBytes { ptr -> Bool in
            var sent = 0
            while sent < data.count {
                let n = Darwin.send(fd, ptr.baseAddress! + sent, data.count - sent, 0)
                if n <= 0 { return false }
                sent += n
            }
            return true
        }
    }

    /// Receive all data until the server closes the connection. Blocks.
    func receiveAll(timeout: TimeInterval = 10.0) -> Data {
        guard fd >= 0 else { return Data() }

        // Set receive timeout
        var tv = timeval(tv_sec: Int(timeout), tv_usec: 0)
        setsockopt(fd, SOL_SOCKET, SO_RCVTIMEO, &tv, socklen_t(MemoryLayout<timeval>.size))

        var accumulated = Data()
        var buffer = [UInt8](repeating: 0, count: 65536)

        while true {
            let n = recv(fd, &buffer, buffer.count, 0)
            if n <= 0 { break }
            accumulated.append(contentsOf: buffer[0..<n])
        }

        return accumulated
    }

    func close() {
        if fd >= 0 {
            Darwin.close(fd)
            fd = -1
        }
    }
}

// MARK: - fd_set helpers

private func __darwin_fd_zero(_ set: UnsafeMutablePointer<fd_set>) {
    // Zero out the entire fd_set structure
    memset(set, 0, MemoryLayout<fd_set>.size)
}

private func __darwin_fd_set(_ fd: Int32, _ set: UnsafeMutablePointer<fd_set>) {
    let intOffset = Int(fd) / 32
    let bitOffset = Int(fd) % 32
    withUnsafeMutablePointer(to: &set.pointee) { ptr in
        let raw = UnsafeMutableRawPointer(ptr)
        let current = raw.load(fromByteOffset: intOffset * 4, as: Int32.self)
        raw.storeBytes(of: current | Int32(1 << bitOffset), toByteOffset: intOffset * 4, as: Int32.self)
    }
}
