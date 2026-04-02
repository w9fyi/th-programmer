// DCSProtocol.swift — DCS protocol constants and packet builders

import Foundation

/// DCS protocol constants and packet construction utilities.
/// DCS is used by DCS reflectors (UDP only on port 30051).
enum DCSProtocol {

    /// Default DCS port (UDP only).
    static let port: UInt16 = 30051

    /// Keepalive interval in seconds (Buster uses 10s for DCS).
    static let keepaliveInterval: TimeInterval = 10.0

    /// Connection timeout in seconds.
    static let connectionTimeout: TimeInterval = 10.0

    /// DCS voice frame length (100 bytes).
    static let voiceFrameLength = 100

    /// DCS header frame length (100 bytes).
    static let headerFrameLength = 100

    /// AMBE silence frame (9 bytes) — standard D-STAR silence pattern.
    static let silenceAMBE = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])

    /// Slow data filler (3 bytes).
    static let fillerSlowData = Data([0x16, 0x29, 0xF5])

    /// Maximum voice frames per superframe (0-20).
    static let framesPerSuperframe: UInt8 = 21

    // MARK: - Callsign Formatting

    /// Pad a callsign to exactly 8 characters with trailing spaces.
    static func padCallsign(_ call: String) -> String {
        String(call.uppercased().prefix(8)).padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    /// Format a callsign as ASCII bytes (8 bytes, space-padded).
    static func callsignBytes(_ call: String) -> Data {
        Data(padCallsign(call).utf8.prefix(8))
    }

    // MARK: - Connect Packet

    /// Build a DCS connect/link packet (UDP).
    ///
    /// Format (519 bytes):
    ///   Bytes 0-7:    local callsign (8 bytes, space-padded)
    ///   Byte  8:      local module letter
    ///   Byte  9:      remote module letter
    ///   Byte  10:     0x00
    ///   Bytes 11-518: HTML info string identifying client (per Buster)
    static func buildConnectPacket(callsign: String, localModule: Character = "B", remoteModule: Character) -> Data {
        var packet = Data(count: 519)
        let csBytes = callsignBytes(callsign)
        for (i, b) in csBytes.enumerated() {
            packet[i] = b
        }
        packet[8] = localModule.asciiValue ?? 0x20
        packet[9] = remoteModule.asciiValue ?? 0x20
        packet[10] = 0x00

        // HTML info string — DCS reflectors expect a client identification here.
        // Per Buster: dongle info HTML table. Reflectors may silently reject connections
        // without this field.
        let html = "<table border='0' width='95%%'><tr><td width='4%%'><img border='0' src='dongle.jpg'></td><td width='96%%'><font size='2'><b>DONGLE TH-Programmer 1.0</b></font></td></tr></table>"
        let htmlBytes = Array(html.utf8)
        let copyLen = Swift.min(htmlBytes.count, 508)  // 519 - 11 = 508 bytes available
        for i in 0..<copyLen {
            packet[11 + i] = htmlBytes[i]
        }

        return packet
    }

    /// Build a DCS disconnect packet (UDP).
    ///
    /// Format (519 bytes):
    ///   Bytes 0-7:    local callsign (8 bytes, space-padded)
    ///   Byte  8:      0x20 (space)
    ///   Byte  9:      0x20 (space)
    ///   Byte  10:     0x00
    ///   Bytes 11-518: padding
    static func buildDisconnectPacket(callsign: String) -> Data {
        var packet = Data(count: 519)
        let csBytes = callsignBytes(callsign)
        for (i, b) in csBytes.enumerated() {
            packet[i] = b
        }
        packet[8] = 0x20  // space
        packet[9] = 0x20  // space
        packet[10] = 0x00
        return packet
    }

    // MARK: - Poll/Keepalive Packet

    /// Build a DCS poll/keepalive packet (UDP).
    ///
    /// Format (17 bytes) per Buster:
    ///   Bytes 0-7:   local callsign (8 bytes)
    ///   Byte  8:     0x00 (null separator)
    ///   Bytes 9-16:  reflector callsign (8 bytes, space-padded)
    static func buildPollPacket(callsign: String, reflectorCallsign: String = "", remoteModule: Character = "A") -> Data {
        var packet = Data(count: 17)
        let localCS = callsignBytes(callsign)
        for (i, b) in localCS.enumerated() {
            packet[i] = b
        }
        packet[8] = 0x00  // null separator
        let refCS = callsignBytes(reflectorCallsign)
        for (i, b) in refCS.enumerated() {
            packet[9 + i] = b
        }
        return packet
    }

    // MARK: - Stream ID Generation

    /// Generate a random stream ID for a new transmission.
    static func randomStreamID() -> UInt16 {
        UInt16.random(in: 1...UInt16.max)
    }

    // MARK: - Reflector Hostname

    /// Derive the hostname for a DCS reflector from its number.
    /// Convention: dcs001.dstargateway.org
    static func hostname(number: Int) -> String {
        let num = String(format: "%03d", Swift.max(1, Swift.min(999, number)))
        return "dcs\(num).dstargateway.org"
    }

    // MARK: - Packet Identification

    /// Identify the type of a received DCS packet.
    static func identifyPacket(_ data: Data) -> PacketType {
        guard !data.isEmpty else { return .unknown }

        // DCS voice/header frames are 100 bytes starting with "0001"
        if data.count >= 100 {
            if data[data.startIndex] == 0x30,     // '0'
               data[data.startIndex + 1] == 0x30, // '0'
               data[data.startIndex + 2] == 0x30, // '0'
               data[data.startIndex + 3] == 0x31  // '1'
            {
                let frameType = data[data.startIndex + 14]
                if frameType == 0x00 || frameType == 0x80 {
                    return .header
                }
                return .voice
            }
        }

        // ACK/NAK detection (14 or 19 bytes with "ACK"/"NAK" at offset 10)
        if data.count >= 13, data.count <= 19 {
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
        }

        // 519-byte control (connect echo or extended link response)
        if data.count == 519 {
            return .control
        }

        // Poll response (17 or 22 bytes)
        if data.count == 17 || data.count == 22 {
            return .control
        }

        // Status data (35 bytes with "EEEE" marker)
        if data.count == 35 {
            return .control
        }

        return .unknown
    }

    enum PacketType {
        case header
        case voice
        case control
        case linkAck
        case linkNak
        case unknown
    }
}
