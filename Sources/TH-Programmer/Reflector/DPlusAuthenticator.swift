// DPlusAuthenticator.swift — Authenticates with DPlus auth server to get REF reflector IPs

import Foundation

/// Authenticates with the DPlus trust server (auth.dstargateway.org:20001) via TCP.
///
/// The auth server returns a list of REF reflector IP addresses after validating the callsign.
/// This is required because REF reflector IPs are not published in static host files.
///
/// Protocol (from QnetGateway reference):
///   1. TCP connect to auth.dstargateway.org:20001
///   2. Send 56-byte auth packet (callsign + version + keys)
///   3. Receive stream of variable-length records, each with 2-byte length header
///   4. Each record contains 26-byte host entries: IP(16) + name(9) + flags(1)
///   5. Filter for active REF entries (flags & 0x80)
final class DPlusAuthenticator: @unchecked Sendable {

    nonisolated deinit {}

    /// Auth server hostname.
    static let authHost = "auth.dstargateway.org"

    /// Auth server port (same as DPlus reflector port).
    static let authPort: UInt16 = 20001

    /// Result: reflector name → IP address (e.g., "REF001" → "44.182.25.1")
    struct AuthResult: Sendable {
        let reflectors: [String: String]
        let repeaters: [String: String]
    }

    private let callsign: String
    private let queue = DispatchQueue(label: "com.th-programmer.dplus-auth")

    /// Diagnostic callback — fires with log messages for debugging.
    var onDiagnostic: ((String) -> Void)?

    init(callsign: String) {
        self.callsign = callsign
    }

    // MARK: - Authenticate

    /// Run the auth flow. Calls completion on the main queue with results or nil on failure.
    /// Uses POSIX TCP sockets — NWConnection fails silently on macOS 26 for ad-hoc signed apps.
    func authenticate(completion: @escaping (AuthResult?) -> Void) {
        let diag = onDiagnostic

        // Capture self strongly — the auth object is short-lived and must stay
        // alive until this block completes. The caller creates it as a local variable.
        queue.async {
            let tcp = PosixTCPSocket()

            // Step 1: TCP connect
            diag?("Connecting to \(Self.authHost):\(Self.authPort) via POSIX TCP…")
            guard tcp.connect(host: Self.authHost, port: Self.authPort, timeout: 10.0) else {
                diag?("TCP connect failed")
                tcp.close()
                DispatchQueue.main.async { completion(nil) }
                return
            }
            diag?("TCP connected")

            // Step 2: Send auth packet
            let packet = self.buildAuthPacket()
            let hex = packet.map { String(format: "%02X", $0) }.joined(separator: " ")
            diag?("TX auth: \(hex)")
            guard tcp.sendAll(packet) else {
                diag?("Send failed")
                tcp.close()
                DispatchQueue.main.async { completion(nil) }
                return
            }
            diag?("Auth packet sent (56 bytes)")

            // Step 3: Receive response
            let response = tcp.receiveAll(timeout: 10.0)
            tcp.close()
            diag?("RX done, total: \(response.count) bytes")

            if response.isEmpty {
                diag?("No data received from auth server")
                DispatchQueue.main.async { completion(nil) }
                return
            }

            // Step 4: Parse
            let result = Self.parseAuthResponse(response, diagnostic: diag)
            DispatchQueue.main.async { completion(result) }
        }
    }

    // MARK: - Auth Packet

    /// Build the 56-byte auth packet.
    ///
    /// Format (from QnetGateway DPlusAuthenticator.cpp):
    ///   Bytes 0-3:   0x38, 0xC0, 0x01, 0x00  (length=56, flags=0xC0, type=0x01)
    ///   Bytes 4-11:  callsign (space-padded to 8)
    ///   Bytes 12-19: "DV019999" (client ID)
    ///   Bytes 20-27: spaces (reserved)
    ///   Bytes 28-35: "W7IB2" + spaces (auth key 1, 8 bytes)
    ///   Bytes 36-39: spaces
    ///   Bytes 40-47: "DHS0257" + space (auth key 2, 8 bytes)
    ///   Bytes 48-55: spaces
    private func buildAuthPacket() -> Data {
        var buffer = Data(repeating: 0x20, count: 56)  // fill with spaces

        // Header: length=56 (0x38), flags=0xC0, type=0x01, pad=0x00
        buffer[0] = 0x38
        buffer[1] = 0xC0
        buffer[2] = 0x01
        buffer[3] = 0x00

        // Callsign (8 bytes, space-padded)
        let padded = callsign.uppercased().padding(toLength: 8, withPad: " ", startingAt: 0)
        for (i, byte) in padded.utf8.prefix(8).enumerated() {
            buffer[4 + i] = byte
        }

        // Version string "DV019999"
        let version = "DV019999"
        for (i, byte) in version.utf8.enumerated() {
            buffer[12 + i] = byte
        }

        // Key 1: "W7IB2" at offset 28 (8-byte field, rest stays as spaces)
        let key1 = "W7IB2"
        for (i, byte) in key1.utf8.enumerated() {
            buffer[28 + i] = byte
        }

        // Key 2: "DHS0257" at offset 40 (8-byte field, rest stays as spaces)
        let key2 = "DHS0257"
        for (i, byte) in key2.utf8.enumerated() {
            buffer[40 + i] = byte
        }

        return buffer
    }

    // MARK: - Response Parsing

    /// Parse the auth response stream into reflector/repeater IP mappings.
    ///
    /// The response is a stream of variable-length records. Each record:
    ///   Bytes 0-1:  Length header — len = (byte[1] & 0x0F) * 256 + byte[0]
    ///               Flags in byte[1] upper nibble: must have 0xC0 set
    ///   Byte  2:    Sub-type (must be 0x01)
    ///   Byte  3:    Padding (0x00)
    ///   Bytes 4-7:  Reserved
    ///   Bytes 8+:   26-byte host entries until end of record
    ///
    /// Each host entry (26 bytes):
    ///   Bytes 0-15:  IP address (null-terminated ASCII, 16 bytes)
    ///   Bytes 16-24: Name (null-terminated ASCII, 9 bytes)
    ///   Byte  25:    Flags (0x80 = active)
    static func parseAuthResponse(_ data: Data, diagnostic: ((String) -> Void)? = nil) -> AuthResult? {
        guard data.count >= 2 else {
            diagnostic?("Response too short: \(data.count) bytes")
            return nil
        }

        var reflectors: [String: String] = [:]
        var repeaters: [String: String] = [:]
        var offset = 0
        var recordNum = 0

        while offset + 2 <= data.count {
            // Read 2-byte length header
            let byte0 = data[data.startIndex + offset]
            let byte1 = data[data.startIndex + offset + 1]

            // Length = lower 4 bits of byte1 * 256 + byte0  (12-bit length)
            let recordLen = Int(byte1 & 0x0F) * 256 + Int(byte0)

            // Validate flags: upper nibble of byte1 must have 0xC0 set
            let flags = byte1 & 0xC0
            if flags != 0xC0 {
                diagnostic?("Record \(recordNum) at offset \(offset): bad flags 0x\(String(format: "%02X", byte1)) (expected 0xC0 in upper nibble)")
                break
            }

            if recordLen < 8 {
                diagnostic?("Record \(recordNum) at offset \(offset): too short (len=\(recordLen))")
                break
            }

            if offset + recordLen > data.count {
                diagnostic?("Record \(recordNum) at offset \(offset): extends past data (len=\(recordLen), available=\(data.count - offset))")
                // Parse what we can
                break
            }

            // Validate sub-type at byte 2
            if offset + 2 < data.count {
                let subType = data[data.startIndex + offset + 2]
                if subType != 0x01 {
                    diagnostic?("Record \(recordNum) at offset \(offset): unexpected sub-type 0x\(String(format: "%02X", subType))")
                }
            }

            // Parse 26-byte host entries starting at offset 8 within this record
            var entryOffset = offset + 8
            var entryCount = 0
            while entryOffset + 26 <= offset + recordLen {
                let ipStart = data.startIndex + entryOffset
                let ipBytes = data[ipStart ..< ipStart + 16]
                let ip = String(bytes: ipBytes, encoding: .ascii)?
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces) ?? ""

                let nameStart = data.startIndex + entryOffset + 16
                let nameBytes = data[nameStart ..< nameStart + 9]
                let name = String(bytes: nameBytes, encoding: .ascii)?
                    .trimmingCharacters(in: .controlCharacters)
                    .trimmingCharacters(in: .whitespaces) ?? ""

                let activeFlag = data[data.startIndex + entryOffset + 25]
                let active = (activeFlag & 0x80) == 0x80

                if !ip.isEmpty, !name.isEmpty, active {
                    let upperName = name.uppercased()
                    if upperName.hasPrefix("REF") {
                        let refName = String(upperName.prefix(6))
                        reflectors[refName] = ip
                    } else {
                        repeaters[upperName] = ip
                    }
                }

                entryOffset += 26
                entryCount += 1
            }

            diagnostic?("Record \(recordNum): len=\(recordLen), entries=\(entryCount)")
            recordNum += 1
            offset += recordLen
        }

        diagnostic?("Parsed \(recordNum) records: \(reflectors.count) reflectors, \(repeaters.count) repeaters")
        return AuthResult(reflectors: reflectors, repeaters: repeaters)
    }
}
