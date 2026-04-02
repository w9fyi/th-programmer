// DPlusProtocol.swift — DPlus protocol constants and packet builders

import Foundation

/// DPlus protocol constants and packet construction utilities.
/// DPlus is used by REF reflectors (UDP only on port 20001).
enum DPlusProtocol {

    /// Default DPlus port (UDP — all three D-Star protocols use UDP for the link).
    static let port: UInt16 = 20001

    /// Keepalive interval in seconds.
    static let keepaliveInterval: TimeInterval = 1.0

    /// Connection timeout in seconds (per step).
    static let stepTimeout: TimeInterval = 5.0

    /// Client version string embedded in login packets.
    static let versionString = "DV019999"

    // MARK: - Connect Packet (CT_LINK1)

    /// Build a DPlus connect request (5 bytes).
    /// Sent first to initiate the connection handshake.
    static func buildConnectPacket() -> Data {
        Data([0x05, 0x00, 0x18, 0x00, 0x01])
    }

    // MARK: - Login Packet (CT_LINK2)

    /// Build a DPlus login packet (28 bytes).
    /// Sent after receiving the connect echo.
    /// Format: [0x1C, 0xC0, 0x04, 0x00] + repeater(16) + "DV019999"(8)
    /// The repeater field is 16 bytes (callsign space-padded to 16).
    /// Per Buster: struct { char repeater[16]; char magic[8]; } module;
    static func buildLoginPacket(callsign: String) -> Data {
        var packet = Data([0x1C, 0xC0, 0x04, 0x00])
        // 16-byte repeater field (callsign padded to 16 with spaces)
        let padded16 = String(callsign.uppercased().prefix(16))
            .padding(toLength: 16, withPad: " ", startingAt: 0)
        packet.append(contentsOf: padded16.utf8.prefix(16))
        // 8-byte version string "DV019999"
        packet.append(contentsOf: versionString.utf8.prefix(8))
        return packet
    }

    // MARK: - Disconnect Packet (CT_UNLINK)

    /// Build a DPlus disconnect packet (5 bytes).
    /// Convention: send twice for reliability.
    static func buildDisconnectPacket() -> Data {
        Data([0x05, 0x00, 0x18, 0x00, 0x00])
    }

    // MARK: - Keepalive / Poll Packet

    /// Build a DPlus keepalive/poll packet (3 bytes).
    static func buildKeepalivePacket() -> Data {
        Data([0x03, 0x60, 0x00])
    }

    // MARK: - Callsign Formatting

    /// Pad a callsign to exactly 8 characters with trailing spaces.
    static func padCallsign(_ call: String) -> String {
        String(call.uppercased().prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    // MARK: - Packet Identification

    /// Identify a received DPlus packet type.
    static func identifyPacket(_ data: Data) -> PacketType {
        guard !data.isEmpty else { return .unknown }
        let count = data.count

        // Connect echo / disconnect (5 bytes: 05 00 18 00 xx)
        if count == 5,
           data[0] == 0x05, data[1] == 0x00, data[2] == 0x18, data[3] == 0x00 {
            if data[4] == 0x01 { return .connectEcho }
            if data[4] == 0x00 { return .disconnect }
        }

        // Login ACK (8 bytes: 08 C0 04 00 "OKRW")
        if count == 8,
           data[0] == 0x08, data[1] == 0xC0, data[2] == 0x04, data[3] == 0x00 {
            if data[4] == 0x4F, data[5] == 0x4B { return .loginAck }    // "OK..."
            if data[4] == 0x42, data[5] == 0x55 { return .loginNack }   // "BU..." (BUSY)
        }

        // Keepalive echo (3 bytes: 03 60 00)
        if count == 3,
           data[0] == 0x03, data[1] == 0x60, data[2] == 0x00 {
            return .keepalive
        }

        // DV Header (58 bytes, starts with length 0x3A, 0x80, then "DSVT")
        if count == 58,
           data[0] == 0x3A, data[1] == 0x80,
           data[2] == 0x44, data[3] == 0x53, data[4] == 0x56, data[5] == 0x54 {
            return .header
        }

        // DV Voice frame (29 bytes, starts with 0x1D, 0x80, then "DSVT")
        if count == 29,
           data[0] == 0x1D, data[1] == 0x80,
           data[2] == 0x44, data[3] == 0x53, data[4] == 0x56, data[5] == 0x54 {
            return .voice
        }

        // DV Last frame (32 bytes, starts with 0x20, 0x80, then "DSVT")
        if count == 32,
           data[0] == 0x20, data[1] == 0x80,
           data[2] == 0x44, data[3] == 0x53, data[4] == 0x56, data[5] == 0x54 {
            return .lastVoice
        }

        return .unknown
    }

    enum PacketType {
        case connectEcho
        case loginAck
        case loginNack
        case disconnect
        case keepalive
        case header
        case voice
        case lastVoice
        case unknown
    }
}
