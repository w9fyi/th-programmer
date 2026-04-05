// DExtraProtocol.swift — DExtra protocol constants and packet builders

import Foundation

/// DExtra protocol constants and packet construction utilities.
/// DExtra is used by REF and XRF reflectors (UDP only on port 30001).
enum DExtraProtocol {

    /// Default DExtra port (UDP only).
    static let port: UInt16 = 30001

    /// Keepalive interval in seconds (xlxd expects every 3s, timeout at 30s).
    static let keepaliveInterval: TimeInterval = 3.0

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
        // Format: 11 bytes total per DroidStar xrf.cpp / xlxd cdextraprotocol.cpp
        //   Bytes 0-7: callsign (8 bytes, space-padded)
        //   Byte  8:   local module letter (same as remote for hotspot/dongle clients)
        //   Byte  9:   remote module letter ('A'-'Z')
        //   Byte  10:  revision (0x0B = modern client, per DroidStar/UP4DAR)
        var packet = Data(callsignBytes(callsign))
        packet.append(contentsOf: String(module).utf8.prefix(1))
        packet.append(contentsOf: String(remoteModule).utf8.prefix(1))
        packet.append(0x0B)  // revision 1 — modern client identifier
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
    ///
    /// DExtra ACK/NAK detection per ircDDBGateway DExtraHandler.cpp:
    /// The reflector echoes back our 11-byte link packet. If the last byte
    /// is changed from 0x00 to a non-zero value (typically the module letter),
    /// it's an ACK. If unchanged (still 0x00), it's a NAK/rejection.
    static func identifyPacket(_ data: Data) -> PacketType {
        guard !data.isEmpty else { return .unknown }
        let s = data.startIndex

        // DSVT voice/header packets (start with "DSVT" magic)
        if data.count >= 27,
           data[s] == 0x44,     // D
           data[s + 1] == 0x53, // S
           data[s + 2] == 0x56, // V
           data[s + 3] == 0x54  // T
        {
            let frameType = data[s + 4]
            if frameType == 0x10 { return .header }
            if frameType == 0x20 { return .voice }
        }

        // Keepalive from server: 9 bytes (callsign + null)
        if data.count == 9 {
            return .keepalive
        }

        // Link ACK: some reflectors (XLX/XRF) send a 14-byte response with
        // "ACK" at bytes 10-12: [callsign(8)][modules(2)][A][C][K][0x00]
        if data.count == 14,
           data[s + 10] == 0x41, // A
           data[s + 11] == 0x43, // C
           data[s + 12] == 0x4B  // K
        {
            return .linkAck
        }

        // Link NAK: 14 bytes with "NAK" at bytes 10-12
        if data.count == 14,
           data[s + 10] == 0x4E, // N
           data[s + 11] == 0x41, // A
           data[s + 12] == 0x4B  // K
        {
            return .linkNak
        }

        // 11-byte control packets: link ACK, link NAK, or unlink
        // Per classic DExtra protocol (ircDDBGateway):
        //   - Unlink: bytes 8-9 are both 0x20 (space)
        //   - Link ACK: last byte (10) is non-zero (reflector changed it)
        //   - Link NAK: last byte (10) is 0x00 (echoed back unchanged)
        if data.count == 11 {
            if data[s + 8] == 0x20, data[s + 9] == 0x20 {
                return .unlink
            }
            if data[s + 10] != 0x00 {
                return .linkAck
            }
            return .linkNak
        }

        return .unknown
    }

    enum PacketType: CustomStringConvertible {
        case header
        case voice
        case linkAck
        case linkNak
        case keepalive
        case unlink
        case unknown

        var description: String {
            switch self {
            case .header: return "header"
            case .voice: return "voice"
            case .linkAck: return "linkAck"
            case .linkNak: return "linkNak"
            case .keepalive: return "keepalive"
            case .unlink: return "unlink"
            case .unknown: return "unknown"
            }
        }
    }
}
