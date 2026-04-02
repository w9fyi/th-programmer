// TerminalModeProtocol.swift — JARL/Icom D-STAR Terminal Mode serial protocol
//
// Protocol reference: QnetGateway/QnetITAP.cpp (n7tae) and DStarRepeater/IcomController.cpp (g4klx)
//
// Serial: 38400 baud, 8N1, no flow control
// Frame: [length][type][payload...] where length = total bytes including length+type
// Idle fill: 0xFF
//
// The TH-D75 in "Reflector TERM Mode" (Menu 650) speaks this protocol over
// Bluetooth SPP or USB serial. BlueDV uses this same protocol path.

import Foundation

enum TerminalModeProtocol {

    // MARK: - Serial Configuration

    static let baudRate: Int = 38400

    // MARK: - Frame Types (radio → host)

    /// Pong response to ping.
    static let typePong: UInt8 = 0x03

    /// Header from radio (radio started TX).
    static let typeHeaderFromRadio: UInt8 = 0x10

    /// Header ACK from radio (acknowledging our header).
    static let typeHeaderAckFromRadio: UInt8 = 0x11

    /// Voice data from radio (radio TX voice frame).
    static let typeVoiceFromRadio: UInt8 = 0x12

    /// Data ACK from radio (acknowledging our voice frame).
    static let typeDataAckFromRadio: UInt8 = 0x13

    // MARK: - Frame Types (host → radio)

    /// Ping (connection check).
    static let typePing: UInt8 = 0x02

    /// Header to radio (network RX header).
    static let typeHeaderToRadio: UInt8 = 0x20

    /// Header ACK to radio (acknowledging radio's header).
    static let typeHeaderAckToRadio: UInt8 = 0x21

    /// Voice data to radio (network RX voice frame).
    static let typeVoiceToRadio: UInt8 = 0x22

    /// Data ACK to radio (acknowledging radio's voice frame).
    static let typeDataAckToRadio: UInt8 = 0x23

    // MARK: - Timing

    /// Delay between poll bytes during handshake (ms).
    static let pollIntervalMs: Int = 5

    /// Time to wait for pong after ping (seconds).
    static let pongTimeout: TimeInterval = 2.0

    /// Overall handshake timeout (seconds).
    static let handshakeTimeout: TimeInterval = 15.0

    /// ACK timeout for terminal mode (seconds).
    static let ackTimeout: TimeInterval = 0.06

    /// Inactivity timeout before reconnect (seconds).
    static let inactivityTimeout: TimeInterval = 10.0

    /// Keepalive ping interval when connected (seconds).
    static let keepaliveInterval: TimeInterval = 1.0

    // MARK: - Handshake Packets

    /// Poll packet — sent repeatedly to get radio's attention.
    /// Two 0xFF bytes (idle fill pattern).
    static func buildPoll() -> Data {
        Data([0xFF, 0xFF])
    }

    /// Ping packet — sent after polls to request pong.
    static func buildPing() -> Data {
        Data([0x02, 0x02])
    }

    // MARK: - ACK Packets

    /// Header ACK to radio — acknowledges radio's TX header.
    static func buildHeaderAck() -> Data {
        Data([0x03, typeHeaderAckToRadio, 0x00])
    }

    /// Data ACK to radio — acknowledges radio's TX voice frame.
    static func buildDataAck(sequence: UInt8) -> Data {
        Data([0x03, typeDataAckToRadio, sequence])
    }

    // MARK: - Header Packet (host → radio)

    /// Build a header packet to send to the radio (network → radio).
    /// Total: 41 bytes = [0x29][0x20][flags(3)][rpt2(8)][rpt1(8)][ur(8)][my(8)][nm(4)]
    static func buildHeader(
        myCallsign: String,
        yourCallsign: String = "CQCQCQ  ",
        rpt1Callsign: String = "DIRECT  ",
        rpt2Callsign: String = "        "
    ) -> Data {
        var packet = Data(count: 41)

        // Length
        packet[0] = 0x29  // 41

        // Type: header to radio
        packet[1] = typeHeaderToRadio

        // Flag bytes (3)
        packet[2] = 0x00
        packet[3] = 0x00
        packet[4] = 0x00

        // RPT2 callsign (8 bytes)
        writeCallsign(rpt2Callsign, to: &packet, offset: 5)

        // RPT1 callsign (8 bytes) — "DIRECT  " for terminal mode
        writeCallsign(rpt1Callsign, to: &packet, offset: 13)

        // YOUR callsign (8 bytes)
        writeCallsign(yourCallsign, to: &packet, offset: 21)

        // MY callsign (8 bytes)
        writeCallsign(myCallsign, to: &packet, offset: 29)

        // MY suffix/name (4 bytes)
        packet[37] = 0x20; packet[38] = 0x20; packet[39] = 0x20; packet[40] = 0x20

        return packet
    }

    // MARK: - Voice Packet (host → radio)

    /// Build a voice packet to send to the radio (network → radio).
    /// Total: 16 bytes = [0x10][0x22][txCounter][seqCounter][ambe(9)][slow(3)]
    static func buildVoice(
        txCounter: UInt8,
        seqCounter: UInt8,
        ambe: Data,
        slowData: Data
    ) -> Data {
        var packet = Data(count: 16)

        // Length
        packet[0] = 0x10  // 16

        // Type: voice to radio
        packet[1] = typeVoiceToRadio

        // TX counter (increments for each frame in transmission)
        packet[2] = txCounter

        // Sequence counter (0-20 mod 21, bit 6 = last frame)
        packet[3] = seqCounter

        // AMBE data (9 bytes)
        for i in 0..<Swift.min(9, ambe.count) {
            packet[4 + i] = ambe[ambe.startIndex + i]
        }

        // Slow data (3 bytes)
        for i in 0..<Swift.min(3, slowData.count) {
            packet[13 + i] = slowData[slowData.startIndex + i]
        }

        return packet
    }

    // MARK: - Frame Parsing

    /// Identify a received frame type.
    /// Returns nil if the data is too short or invalid.
    static func parseFrame(_ data: Data) -> ParsedFrame? {
        guard data.count >= 2 else { return nil }

        let length = data[data.startIndex]
        let type = data[data.startIndex + 1]

        guard data.count >= Int(length) else { return nil }

        switch type {
        case typePong:
            return .pong

        case typeHeaderFromRadio:
            guard data.count >= 41 else { return nil }
            return .header(data)

        case typeVoiceFromRadio:
            guard data.count >= 16 else { return nil }
            return .voice(data)

        case typeHeaderAckFromRadio:
            return .headerAck

        case typeDataAckFromRadio:
            let seq = data.count >= 3 ? data[data.startIndex + 2] : 0
            return .dataAck(sequence: seq)

        default:
            return .unknown(type: type)
        }
    }

    /// Extract callsign fields from a header frame (type 0x10 from radio).
    /// Returns (rpt2, rpt1, your, my, suffix) or nil.
    static func parseHeader(_ data: Data) -> (rpt2: String, rpt1: String, your: String, my: String, suffix: String)? {
        guard data.count >= 41 else { return nil }
        let s = data.startIndex
        let rpt2 = extractCallsign(from: data, offset: 5)
        let rpt1 = extractCallsign(from: data, offset: 13)
        let your = extractCallsign(from: data, offset: 21)
        let my = extractCallsign(from: data, offset: 29)
        let suffix: String
        if data.count >= 41 {
            let sfxBytes = data[(s + 37)..<(s + 41)]
            suffix = String(bytes: sfxBytes, encoding: .ascii)?.trimmingCharacters(in: .whitespaces) ?? ""
        } else {
            suffix = ""
        }
        return (rpt2: rpt2, rpt1: rpt1, your: your, my: my, suffix: suffix)
    }

    /// Extract voice data from a voice frame (type 0x12 from radio).
    /// Returns (txCounter, seqCounter, ambe[9], slowData[3]) or nil.
    static func parseVoice(_ data: Data) -> (txCounter: UInt8, seqCounter: UInt8, ambe: Data, slowData: Data)? {
        guard data.count >= 16 else { return nil }
        let s = data.startIndex
        let txCounter = data[s + 2]
        let seqCounter = data[s + 3]
        let ambe = Data(data[(s + 4)..<(s + 13)])
        let slowData = Data(data[(s + 13)..<(s + 16)])
        return (txCounter: txCounter, seqCounter: seqCounter, ambe: ambe, slowData: slowData)
    }

    // MARK: - Parsed Frame

    enum ParsedFrame {
        case pong
        case header(Data)
        case voice(Data)
        case headerAck
        case dataAck(sequence: UInt8)
        case unknown(type: UInt8)
    }

    // MARK: - Helpers

    private static func writeCallsign(_ call: String, to data: inout Data, offset: Int) {
        let padded = call.padding(toLength: 8, withPad: " ", startingAt: 0)
        for (i, byte) in padded.utf8.prefix(8).enumerated() {
            data[offset + i] = byte
        }
    }

    private static func extractCallsign(from data: Data, offset: Int) -> String {
        let start = data.startIndex + offset
        let end = Swift.min(start + 8, data.endIndex)
        guard start < data.endIndex else { return "" }
        let bytes = data[start..<end]
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}
