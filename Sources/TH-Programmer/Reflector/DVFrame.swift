// DVFrame.swift — D-STAR voice frame model
//
// DSVT frame layout (from Buster / g4klx reference):
//   Offset 0-3:   "DSVT" magic
//   Offset 4:     type (0x10=header, 0x20=voice)
//   Offset 5-8:   unknown {0x00, 0x00, 0x00, 0x20}
//   Offset 9-11:  band {0x00, 0x02, 0x01}
//   Offset 12-13: stream ID (little-endian)
//   Offset 14:    sequence (0-20, bit 0x40 = last frame, 0x80 = header)
//   Offset 15+:   header data or voice data
//
// Header data (41 bytes at offset 15):
//   15-17:  flags {0x00, 0x00, 0x00}
//   18-25:  RPT2 callsign (8 bytes)
//   26-33:  RPT1 callsign (8 bytes)
//   34-41:  YOUR callsign (8 bytes)
//   42-49:  MY callsign (8 bytes)
//   50-53:  MY suffix (4 bytes)
//   54-55:  CRC-CCITT (2 bytes)
//
// Voice data (12 bytes at offset 15):
//   15-23:  AMBE voice (9 bytes)
//   24-26:  slow data (3 bytes)

import Foundation

/// A single D-STAR DV (Digital Voice) frame.
struct DVFrame: Equatable, Sendable {

    /// Stream identifier — same for all frames in one transmission.
    let streamID: UInt16

    /// Frame counter 0-20 within a superframe. Bit 6 (0x40) set on the last frame.
    let frameCounter: UInt8

    /// 9 bytes of AMBE 3600x2450 voice data.
    let ambeData: Data

    /// 3 bytes of slow data (callsign text, GPS, etc.).
    let slowData: Data

    /// Source callsign extracted from the stream header (set on first frame).
    var sourceCallsign: String = ""

    /// True if this is the last frame of the transmission.
    var isLastFrame: Bool {
        frameCounter & 0x40 != 0
    }

    /// The sequence number within the superframe (0-20).
    var sequenceNumber: UInt8 {
        frameCounter & 0x1F
    }

    // MARK: - DSVT Constants

    /// Unknown bytes in DSVT prefix (offsets 5-8).
    private static let dsvtUnknown: [UInt8] = [0x00, 0x00, 0x00, 0x20]

    /// Band bytes in DSVT prefix (offsets 9-11).
    private static let dsvtBand: [UInt8] = [0x00, 0x02, 0x01]

    /// DPlus end-of-stream pattern (appended after slow data on last frame).
    private static let dplusEndPattern: [UInt8] = [0x55, 0x55, 0x55]

    // MARK: - DExtra Packet Parsing

    /// Parse a 27-byte DExtra voice packet into a DVFrame.
    static func parseDExtra(_ data: Data) -> DVFrame? {
        guard data.count >= 27 else { return nil }

        let s = data.startIndex

        // Check for "DSVT" magic
        guard data[s] == 0x44, data[s + 1] == 0x53,
              data[s + 2] == 0x56, data[s + 3] == 0x54
        else { return nil }

        // Byte 4: 0x20 = voice data frame
        guard data[s + 4] == 0x20 else { return nil }

        let streamID = UInt16(data[s + 12]) | (UInt16(data[s + 13]) << 8)
        let frameCounter = data[s + 14]

        let ambeStart = s + 15
        let ambeData = data[ambeStart..<(ambeStart + 9)]
        let slowData = data[(ambeStart + 9)..<(ambeStart + 12)]

        return DVFrame(
            streamID: streamID,
            frameCounter: frameCounter,
            ambeData: Data(ambeData),
            slowData: Data(slowData)
        )
    }

    /// Parse a DExtra header frame (56 bytes, type 0x10) to extract callsign info.
    static func parseDExtraHeader(_ data: Data) -> (streamID: UInt16, myCall: String, yourCall: String, rpt1: String, rpt2: String)? {
        guard data.count >= 56 else { return nil }

        let s = data.startIndex

        guard data[s] == 0x44, data[s + 1] == 0x53,
              data[s + 2] == 0x56, data[s + 3] == 0x54,
              data[s + 4] == 0x10
        else { return nil }

        let streamID = UInt16(data[s + 12]) | (UInt16(data[s + 13]) << 8)

        // Header fields after 15-byte DSVT prefix + 3-byte flags:
        let rpt2 = extractCallsign(from: data, offset: 18)
        let rpt1 = extractCallsign(from: data, offset: 26)
        let yourCall = extractCallsign(from: data, offset: 34)
        let myCall = extractCallsign(from: data, offset: 42)

        return (streamID: streamID, myCall: myCall, yourCall: yourCall, rpt1: rpt1, rpt2: rpt2)
    }

    // MARK: - DExtra Packet Construction

    /// Build a 27-byte DExtra voice packet.
    func serializeDExtra() -> Data {
        var packet = Data(count: 27)

        // Magic "DSVT"
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54

        // Frame type: voice
        packet[4] = 0x20

        // Unknown bytes {0x00, 0x00, 0x00, 0x20}
        packet[5] = 0x00; packet[6] = 0x00; packet[7] = 0x00; packet[8] = 0x20

        // Band bytes {0x00, 0x02, 0x01}
        packet[9] = 0x00; packet[10] = 0x02; packet[11] = 0x01

        // Stream ID (little-endian)
        packet[12] = UInt8(streamID & 0xFF)
        packet[13] = UInt8(streamID >> 8)

        // Frame counter
        packet[14] = frameCounter

        // AMBE data (9 bytes) at offsets 15-23
        for i in 0..<Swift.min(9, ambeData.count) {
            packet[15 + i] = ambeData[ambeData.startIndex + i]
        }

        // Slow data (3 bytes) at offsets 24-26
        for i in 0..<Swift.min(3, slowData.count) {
            packet[24 + i] = slowData[slowData.startIndex + i]
        }

        return packet
    }

    /// Build a 56-byte DExtra header packet for starting a transmission.
    static func buildDExtraHeader(
        streamID: UInt16,
        myCallsign: String,
        yourCallsign: String = "CQCQCQ  ",
        rpt1Callsign: String = "        ",
        rpt2Callsign: String = "        "
    ) -> Data {
        var packet = Data(count: 56)

        // Magic "DSVT"
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54

        // Frame type: header
        packet[4] = 0x10

        // Unknown bytes
        packet[5] = 0x00; packet[6] = 0x00; packet[7] = 0x00; packet[8] = 0x20

        // Band bytes
        packet[9] = 0x00; packet[10] = 0x02; packet[11] = 0x01

        // Stream ID (little-endian)
        packet[12] = UInt8(streamID & 0xFF)
        packet[13] = UInt8(streamID >> 8)

        // Header sequence marker
        packet[14] = 0x80

        // Header flags (3 bytes)
        packet[15] = 0x00; packet[16] = 0x00; packet[17] = 0x00

        // RPT2 callsign (8 bytes) at offset 18
        writeCallsign(rpt2Callsign, to: &packet, offset: 18)
        // RPT1 callsign (8 bytes) at offset 26
        writeCallsign(rpt1Callsign, to: &packet, offset: 26)
        // YOUR callsign (8 bytes) at offset 34
        writeCallsign(yourCallsign, to: &packet, offset: 34)
        // MY callsign (8 bytes) at offset 42
        writeCallsign(myCallsign, to: &packet, offset: 42)

        // MY suffix (4 bytes) at offset 50 — zero-filled (already zero)

        // CRC-CCITT over header data (offsets 15-53, 39 bytes)
        let crc = dstarCRC(data: packet, from: 15, count: 39)
        packet[54] = UInt8(crc & 0xFF)
        packet[55] = UInt8(crc >> 8)

        return packet
    }

    // MARK: - DCS Packet Parsing

    /// Parse a 100-byte DCS voice packet into a DVFrame.
    /// DCS format uses "0001" tag, not DSVT.
    static func parseDCS(_ data: Data) -> DVFrame? {
        guard data.count >= 100 else { return nil }

        let s = data.startIndex

        // Check for "0001" tag
        guard data[s] == 0x30, data[s + 1] == 0x30,
              data[s + 2] == 0x30, data[s + 3] == 0x31
        else { return nil }

        let streamID = UInt16(data[s + 8]) | (UInt16(data[s + 9]) << 8)
        let frameCounter = data[s + 14]

        // Header frames have frameCounter 0x00 or 0x80 — skip those
        if frameCounter == 0x00 || frameCounter == 0x80 { return nil }

        let ambeStart = s + 15
        let ambeData = data[ambeStart..<(ambeStart + 9)]
        let slowData = data[(ambeStart + 9)..<(ambeStart + 12)]

        return DVFrame(
            streamID: streamID,
            frameCounter: frameCounter,
            ambeData: Data(ambeData),
            slowData: Data(slowData)
        )
    }

    /// Parse a DCS header frame (100 bytes) to extract callsign info.
    static func parseDCSHeader(_ data: Data) -> (streamID: UInt16, myCall: String, yourCall: String, rpt1: String, rpt2: String)? {
        guard data.count >= 100 else { return nil }

        let s = data.startIndex

        guard data[s] == 0x30, data[s + 1] == 0x30,
              data[s + 2] == 0x30, data[s + 3] == 0x31
        else { return nil }

        let frameCounter = data[s + 14]
        guard frameCounter == 0x00 || frameCounter == 0x80 else { return nil }

        let streamID = UInt16(data[s + 8]) | (UInt16(data[s + 9]) << 8)

        let rpt2 = extractCallsign(from: data, offset: 27)
        let rpt1 = extractCallsign(from: data, offset: 35)
        let yourCall = extractCallsign(from: data, offset: 43)
        let myCall = extractCallsign(from: data, offset: 51)

        return (streamID: streamID, myCall: myCall, yourCall: yourCall, rpt1: rpt1, rpt2: rpt2)
    }

    // MARK: - DCS Packet Construction

    /// Build a 100-byte DCS voice packet.
    func serializeDCS(localCallsign: String = "        ", remoteModule: Character = "A") -> Data {
        var packet = Data(count: 100)

        // Tag "0001"
        packet[0] = 0x30; packet[1] = 0x30; packet[2] = 0x30; packet[3] = 0x31

        // Stream ID (little-endian)
        packet[8] = UInt8(streamID & 0xFF)
        packet[9] = UInt8(streamID >> 8)

        // Frame counter
        packet[14] = frameCounter

        // AMBE data (9 bytes) at offsets 15-23
        for i in 0..<Swift.min(9, ambeData.count) {
            packet[15 + i] = ambeData[ambeData.startIndex + i]
        }

        // Slow data (3 bytes) at offsets 24-26
        for i in 0..<Swift.min(3, slowData.count) {
            packet[24 + i] = slowData[slowData.startIndex + i]
        }

        return packet
    }

    /// Build a 100-byte DCS header packet for starting a transmission.
    static func buildDCSHeader(
        streamID: UInt16,
        myCallsign: String,
        yourCallsign: String = "CQCQCQ  ",
        rpt1Callsign: String = "        ",
        rpt2Callsign: String = "        ",
        remoteModule: Character = "A"
    ) -> Data {
        var packet = Data(count: 100)

        // Tag "0001"
        packet[0] = 0x30; packet[1] = 0x30; packet[2] = 0x30; packet[3] = 0x31

        // Stream ID (little-endian)
        packet[8] = UInt8(streamID & 0xFF)
        packet[9] = UInt8(streamID >> 8)

        // Frame counter (0x00 = header)
        packet[14] = 0x00

        // Callsign fields
        writeCallsign(rpt2Callsign, to: &packet, offset: 27)
        writeCallsign(rpt1Callsign, to: &packet, offset: 35)
        writeCallsign(yourCallsign, to: &packet, offset: 43)
        writeCallsign(myCallsign, to: &packet, offset: 51)

        return packet
    }

    // MARK: - MMDVM Conversion

    /// Parse an MMDVM D-STAR voice data payload (12 bytes: 9 AMBE + 3 slow data) into a DVFrame.
    static func fromMMDVM(_ payload: Data, streamID: UInt16, frameCounter: UInt8) -> DVFrame? {
        guard payload.count >= 12 else { return nil }

        let ambeData = Data(payload[payload.startIndex..<(payload.startIndex + 9)])
        let slowData = Data(payload[(payload.startIndex + 9)..<(payload.startIndex + 12)])

        return DVFrame(
            streamID: streamID,
            frameCounter: frameCounter,
            ambeData: ambeData,
            slowData: slowData
        )
    }

    /// Convert this DVFrame to an MMDVM D-STAR voice data frame.
    func toMMDVM() -> Data {
        return MMDVMProtocol.buildDStarData(ambe: ambeData, slowData: slowData)
    }

    /// Parse an MMDVM D-STAR header payload (41 bytes) to extract callsign info.
    static func headerFromMMDVM(_ payload: Data) -> (myCall: String, yourCall: String, rpt1: String, rpt2: String)? {
        guard payload.count >= 39 else { return nil }

        let rpt2 = extractCallsign(from: payload, offset: 3)
        let rpt1 = extractCallsign(from: payload, offset: 11)
        let yourCall = extractCallsign(from: payload, offset: 19)
        let myCall = extractCallsign(from: payload, offset: 27)

        return (myCall: myCall, yourCall: yourCall, rpt1: rpt1, rpt2: rpt2)
    }

    // MARK: - DPlus Packet Parsing

    /// Parse a DPlus voice frame (29 or 32 bytes).
    /// DPlus format: 2-byte length/flags prefix + DSVT data.
    ///   Bytes 0-1:   length prefix (0x1D 0x80 for voice, 0x20 0x80 for last)
    ///   Bytes 2-5:   "DSVT" magic
    ///   Byte  6:     0x20 (voice frame type)
    ///   Bytes 7-10:  unknown {0x00, 0x00, 0x00, 0x20}
    ///   Bytes 11-13: band {0x00, 0x02, 0x01}
    ///   Bytes 14-15: stream ID (little-endian)
    ///   Byte  16:    frame counter
    ///   Bytes 17-25: 9 bytes AMBE voice data
    ///   Bytes 26-28: 3 bytes slow data
    ///   Bytes 29-31: end pattern (last frame only, 32-byte packet)
    static func parseDPlus(_ data: Data) -> DVFrame? {
        guard data.count >= 29 else { return nil }

        let s = data.startIndex

        // Check 2-byte prefix + "DSVT" magic
        guard (data[s] == 0x1D || data[s] == 0x20),
              data[s + 1] == 0x80,
              data[s + 2] == 0x44,  // D
              data[s + 3] == 0x53,  // S
              data[s + 4] == 0x56,  // V
              data[s + 5] == 0x54   // T
        else { return nil }

        // Frame type at offset 6 must be 0x20 (voice)
        guard data[s + 6] == 0x20 else { return nil }

        let streamID = UInt16(data[s + 14]) | (UInt16(data[s + 15]) << 8)
        let frameCounter = data[s + 16]

        let ambeStart = s + 17
        guard ambeStart + 12 <= data.endIndex else { return nil }
        let ambeData = data[ambeStart..<(ambeStart + 9)]
        let slowData = data[(ambeStart + 9)..<(ambeStart + 12)]

        return DVFrame(
            streamID: streamID,
            frameCounter: frameCounter,
            ambeData: Data(ambeData),
            slowData: Data(slowData)
        )
    }

    /// Parse a DPlus header frame (58 bytes) to extract callsign info.
    /// Format: 2-byte prefix + DSVT header (same layout as DExtra but offset by 2).
    static func parseDPlusHeader(_ data: Data) -> (streamID: UInt16, myCall: String, yourCall: String, rpt1: String, rpt2: String)? {
        guard data.count >= 58 else { return nil }

        let s = data.startIndex

        guard data[s] == 0x3A, data[s + 1] == 0x80,
              data[s + 2] == 0x44, data[s + 3] == 0x53,
              data[s + 4] == 0x56, data[s + 5] == 0x54,
              data[s + 6] == 0x10  // header frame type
        else { return nil }

        let streamID = UInt16(data[s + 14]) | (UInt16(data[s + 15]) << 8)

        // Header fields: prefix(2) + DSVT(15) + flags(3) = offset 20 for rpt2
        let rpt2 = extractCallsign(from: data, offset: 20)
        let rpt1 = extractCallsign(from: data, offset: 28)
        let yourCall = extractCallsign(from: data, offset: 36)
        let myCall = extractCallsign(from: data, offset: 44)

        return (streamID: streamID, myCall: myCall, yourCall: yourCall, rpt1: rpt1, rpt2: rpt2)
    }

    // MARK: - DPlus Packet Construction

    /// Build a DPlus voice packet (29 bytes normal, 32 bytes for last frame).
    func serializeDPlus() -> Data {
        let isLast = isLastFrame
        let size = isLast ? 32 : 29
        var packet = Data(count: size)

        // Length prefix
        packet[0] = isLast ? 0x20 : 0x1D
        packet[1] = 0x80

        // "DSVT" magic
        packet[2] = 0x44; packet[3] = 0x53; packet[4] = 0x56; packet[5] = 0x54

        // Frame type: voice
        packet[6] = 0x20

        // Unknown bytes
        packet[7] = 0x00; packet[8] = 0x00; packet[9] = 0x00; packet[10] = 0x20

        // Band bytes
        packet[11] = 0x00; packet[12] = 0x02; packet[13] = 0x01

        // Stream ID (little-endian)
        packet[14] = UInt8(streamID & 0xFF)
        packet[15] = UInt8(streamID >> 8)

        // Frame counter
        packet[16] = frameCounter

        // AMBE data (9 bytes)
        for i in 0..<Swift.min(9, ambeData.count) {
            packet[17 + i] = ambeData[ambeData.startIndex + i]
        }

        // Slow data (3 bytes)
        for i in 0..<Swift.min(3, slowData.count) {
            packet[26 + i] = slowData[slowData.startIndex + i]
        }

        // End pattern for last frame (3 bytes at offsets 29-31)
        if isLast {
            packet[29] = 0x55; packet[30] = 0x55; packet[31] = 0x55
        }

        return packet
    }

    /// Build a 58-byte DPlus header packet for starting a transmission.
    static func buildDPlusHeader(
        streamID: UInt16,
        myCallsign: String,
        remoteModule: Character,
        yourCallsign: String = "CQCQCQ  ",
        rpt1Callsign: String = "        ",
        rpt2Callsign: String = "        "
    ) -> Data {
        var packet = Data(count: 58)

        // Length prefix (0x803A: top nibble 0x8 = data, low 12 bits = 0x3A = 58)
        packet[0] = 0x3A
        packet[1] = 0x80

        // "DSVT" magic
        packet[2] = 0x44; packet[3] = 0x53; packet[4] = 0x56; packet[5] = 0x54

        // Frame type: header
        packet[6] = 0x10

        // Unknown bytes
        packet[7] = 0x00; packet[8] = 0x00; packet[9] = 0x00; packet[10] = 0x20

        // Band bytes
        packet[11] = 0x00; packet[12] = 0x02; packet[13] = 0x01

        // Stream ID (little-endian)
        packet[14] = UInt8(streamID & 0xFF)
        packet[15] = UInt8(streamID >> 8)

        // Header sequence marker
        packet[16] = 0x80

        // Header flags (3 bytes)
        packet[17] = 0x00; packet[18] = 0x00; packet[19] = 0x00

        // RPT2 callsign (8 bytes) at offset 20
        writeCallsign(rpt2Callsign, to: &packet, offset: 20)
        // RPT1 callsign (8 bytes) at offset 28
        writeCallsign(rpt1Callsign, to: &packet, offset: 28)
        // YOUR callsign (8 bytes) at offset 36
        writeCallsign(yourCallsign, to: &packet, offset: 36)
        // MY callsign (8 bytes) at offset 44
        writeCallsign(myCallsign, to: &packet, offset: 44)

        // MY suffix (4 bytes) at offset 52 — zero-filled

        // DPlus uses 0xFFFF (no checksum) per Buster hasReliableChecksum = NO
        packet[56] = 0xFF
        packet[57] = 0xFF

        return packet
    }

    // MARK: - CRC-CCITT

    /// CRC-CCITT lookup table (polynomial 0x8408, reflected).
    private static let ccittTable: [UInt16] = {
        var table = [UInt16](repeating: 0, count: 256)
        for i in 0..<256 {
            var crc = UInt16(i)
            for _ in 0..<8 {
                if crc & 1 != 0 {
                    crc = (crc >> 1) ^ 0x8408
                } else {
                    crc >>= 1
                }
            }
            table[i] = crc
        }
        return table
    }()

    /// Compute D-STAR CRC-CCITT over a range of bytes in a Data buffer.
    /// Used for DExtra and DCS header checksums.
    static func dstarCRC(data: Data, from start: Int, count: Int) -> UInt16 {
        var crc: UInt16 = 0xFFFF
        for i in start..<(start + count) {
            let byte = data[i]
            crc = (crc >> 8) ^ ccittTable[Int((crc & 0x00FF) ^ UInt16(byte))]
        }
        return ~crc
    }

    // MARK: - Helpers

    private static func extractCallsign(from data: Data, offset: Int) -> String {
        let start = data.startIndex + offset
        let end = Swift.min(start + 8, data.endIndex)
        guard start < data.endIndex else { return "" }
        let bytes = data[start..<end]
        return String(bytes: bytes, encoding: .ascii)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }

    private static func writeCallsign(_ call: String, to data: inout Data, offset: Int) {
        let padded = call.padding(toLength: 8, withPad: " ", startingAt: 0)
        for (i, byte) in padded.utf8.prefix(8).enumerated() {
            data[offset + i] = byte
        }
    }
}
