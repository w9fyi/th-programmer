// DExtraProtocol.swift — DExtra protocol constants and packet builders

import Foundation

/// DExtra protocol constants and packet construction utilities.
/// DExtra is used by REF and XRF reflectors (UDP only on port 30001).
enum DExtraProtocol {

    /// Default DExtra port (UDP only).
    static let port: UInt16 = 30001

    /// Keepalive interval in seconds.
    static let keepaliveInterval: TimeInterval = 5.0

    /// Connection timeout in seconds.
    static let connectionTimeout: TimeInterval = 10.0

    /// Maximum voice frames per superframe (0–20, then repeats).
    static let framesPerSuperframe: UInt8 = 21

    /// AMBE silence frame (9 bytes) — standard D-STAR silence pattern.
    static let silenceAMBE = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])

    /// Slow data filler (3 bytes) — sent when there is no slow data.
    static let fillerSlowData = Data([0x16, 0x29, 0xF5])

    // MARK: - Callsign Formatting

    /// Pad a callsign to exactly 8 characters with trailing spaces.
    static func padCallsign(_ call: String) -> String {
        String(call.uppercased().prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    /// Format a callsign as ASCII bytes (8 bytes, space-padded).
    static func callsignBytes(_ call: String) -> Data {
        Data(padCallsign(call).utf8.prefix(8))
    }

    // MARK: - Registration Packet (UDP)

    /// Build a DExtra link registration packet (UDP).
    ///
    /// Format: 11 bytes for link request
    ///   Bytes 0-7:  callsign (8 bytes, space-padded)
    ///   Byte  8:    module letter (e.g., 'A')
    ///   Byte  9:    remote module letter
    ///   Byte  10:   0x00
    static func buildLinkPacket(callsign: String, module: Character, remoteModule: Character) -> Data {
        var packet = Data(callsignBytes(callsign))
        packet.append(contentsOf: String(module).utf8.prefix(1))
        packet.append(contentsOf: String(remoteModule).utf8.prefix(1))
        packet.append(0x00)
        return packet
    }

    /// Build a DExtra unlink request packet (UDP).
    ///
    /// Format: 11 bytes
    ///   Bytes 0-7:  callsign (8 bytes, space-padded)
    ///   Byte  8:    0x20 (space)
    ///   Byte  9:    0x20 (space)
    ///   Byte  10:   0x00
    static func buildUnlinkPacket(callsign: String) -> Data {
        var packet = Data(callsignBytes(callsign))
        packet.append(0x20) // space
        packet.append(0x20) // space
        packet.append(0x00)
        return packet
    }

    // MARK: - Keepalive Packet (UDP)

    /// Build a keepalive/poll packet (UDP).
    /// Same format as link packet but used periodically to maintain the connection.
    static func buildKeepalivePacket(callsign: String) -> Data {
        var packet = Data(callsignBytes(callsign))
        // 9-byte keepalive: callsign + null
        packet.append(0x00)
        return packet
    }

    // MARK: - Stream ID Generation

    /// Generate a random stream ID for a new transmission.
    static func randomStreamID() -> UInt16 {
        UInt16.random(in: 1...UInt16.max)
    }

    // MARK: - Reflector Hostname

    /// Derive the hostname for a reflector from its type and number.
    /// Convention: ref001.dstargateway.org, xrf012.dstargateway.org, etc.
    static func hostname(type: String, number: Int) -> String {
        let prefix = type.lowercased()
        let num = String(format: "%03d", Swift.max(1, Swift.min(999, number)))
        return "\(prefix)\(num).dstargateway.org"
    }

    // MARK: - Packet Identification

    /// Identify the type of a received DExtra packet.
    static func identifyPacket(_ data: Data) -> PacketType {
        guard !data.isEmpty else { return .unknown }

        // DSVT voice/header packets (start with "DSVT" magic)
        if data.count >= 27,
           data[data.startIndex] == 0x44,     // D
           data[data.startIndex + 1] == 0x53, // S
           data[data.startIndex + 2] == 0x56, // V
           data[data.startIndex + 3] == 0x54  // T
        {
            let frameType = data[data.startIndex + 4]
            if frameType == 0x10 { return .header }
            if frameType == 0x20 { return .voice }
        }

        // Link ACK: ~14 bytes with "ACK" at offset 10
        if data.count >= 13, data.count <= 20 {
            let s = data.startIndex
            if data[s + 10] == 0x41, // A
               data[s + 11] == 0x43, // C
               data[s + 12] == 0x4B  // K
            {
                return .linkAck
            }
            if data[s + 10] == 0x4E, // N
               data[s + 11] == 0x41, // A
               data[s + 12] == 0x4B  // K
            {
                return .linkNak
            }
            if data.count >= 14,
               data[s + 10] == 0x42, // B
               data[s + 11] == 0x55, // U
               data[s + 12] == 0x53, // S
               data[s + 13] == 0x59  // Y
            {
                return .linkBusy
            }
        }

        // Keepalive from server: 9 bytes (callsign + null)
        if data.count == 9 {
            return .keepalive
        }

        // Unlink: 11 bytes with spaces at bytes 8-9
        if data.count == 11 {
            let s = data.startIndex
            if data[s + 8] == 0x20, data[s + 9] == 0x20 {
                return .unlink
            }
            return .control
        }

        return .unknown
    }

    enum PacketType: CustomStringConvertible {
        case header
        case voice
        case control
        case linkAck
        case linkNak
        case linkBusy
        case keepalive
        case unlink
        case unknown

        var description: String {
            switch self {
            case .header: return "header"
            case .voice: return "voice"
            case .control: return "control"
            case .linkAck: return "linkAck"
            case .linkNak: return "linkNak"
            case .linkBusy: return "linkBusy"
            case .keepalive: return "keepalive"
            case .unlink: return "unlink"
            case .unknown: return "unknown"
            }
        }
    }
}
