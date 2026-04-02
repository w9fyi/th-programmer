// DVFrameTests.swift — Tests for DV frame parsing and serialization

import XCTest
@testable import TH_Programmer

final class DVFrameTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Voice Frame Parsing

    func testParseDExtra_validVoiceFrame() {
        var packet = Data(count: 27)
        // DSVT magic
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        // Voice type
        packet[4] = 0x20
        // Unknown bytes
        packet[5] = 0x00; packet[6] = 0x00; packet[7] = 0x00; packet[8] = 0x20
        // Band bytes
        packet[9] = 0x00; packet[10] = 0x02; packet[11] = 0x01
        // Stream ID = 0x1234 (little-endian) at offset 12-13
        packet[12] = 0x34; packet[13] = 0x12
        // Frame counter = 5 at offset 14
        packet[14] = 0x05
        // AMBE data at offset 15 (9 bytes)
        for i in 15..<24 { packet[i] = UInt8(i - 15 + 1) }
        // Slow data at offset 24 (3 bytes)
        packet[24] = 0xAA; packet[25] = 0xBB; packet[26] = 0xCC

        let frame = DVFrame.parseDExtra(packet)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.streamID, 0x1234)
        XCTAssertEqual(frame?.frameCounter, 5)
        XCTAssertEqual(frame?.sequenceNumber, 5)
        XCTAssertFalse(frame?.isLastFrame ?? true)
        XCTAssertEqual(frame?.ambeData.count, 9)
        XCTAssertEqual(frame?.slowData.count, 3)
        XCTAssertEqual(frame?.ambeData[0], 1)
        XCTAssertEqual(frame?.slowData[0], 0xAA)
    }

    func testParseDExtra_lastFrame() {
        var packet = Data(count: 27)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        packet[4] = 0x20
        // Stream ID at offset 12-13
        packet[12] = 0x01; packet[13] = 0x00
        // Frame counter with last-frame flag at offset 14
        packet[14] = 0x45  // frame 5 with last-frame flag (0x40)

        let frame = DVFrame.parseDExtra(packet)
        XCTAssertNotNil(frame)
        XCTAssertTrue(frame!.isLastFrame)
        XCTAssertEqual(frame?.sequenceNumber, 5)
    }

    func testParseDExtra_rejectsWrongMagic() {
        var packet = Data(count: 27)
        packet[0] = 0x00; packet[1] = 0x00; packet[2] = 0x00; packet[3] = 0x00
        packet[4] = 0x20
        XCTAssertNil(DVFrame.parseDExtra(packet))
    }

    func testParseDExtra_rejectsHeaderType() {
        var packet = Data(count: 56)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        packet[4] = 0x10  // header, not voice
        XCTAssertNil(DVFrame.parseDExtra(packet))
    }

    func testParseDExtra_rejectsTooShort() {
        let packet = Data(count: 20)
        XCTAssertNil(DVFrame.parseDExtra(packet))
    }

    func testParseDExtra_rejectsEmpty() {
        XCTAssertNil(DVFrame.parseDExtra(Data()))
    }

    // MARK: - Header Parsing

    func testParseDExtraHeader_extractsCallsigns() {
        var packet = Data(count: 56)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        packet[4] = 0x10  // header type
        // Stream ID at offset 12-13
        packet[12] = 0x99; packet[13] = 0x00

        // Flags at offset 15-17 (zeros)
        // RPT2 at offset 18 (8 bytes)
        let rpt2 = "RPT2    ".utf8
        for (i, b) in rpt2.enumerated() { packet[18 + i] = b }
        // RPT1 at offset 26
        let rpt1 = "RPT1    ".utf8
        for (i, b) in rpt1.enumerated() { packet[26 + i] = b }
        // YOUR at offset 34
        let your = "CQCQCQ  ".utf8
        for (i, b) in your.enumerated() { packet[34 + i] = b }
        // MY at offset 42
        let my = "AI5OS   ".utf8
        for (i, b) in my.enumerated() { packet[42 + i] = b }

        let header = DVFrame.parseDExtraHeader(packet)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.streamID, 0x0099)
        XCTAssertEqual(header?.myCall, "AI5OS")
        XCTAssertEqual(header?.yourCall, "CQCQCQ")
        XCTAssertEqual(header?.rpt1, "RPT1")
        XCTAssertEqual(header?.rpt2, "RPT2")
    }

    func testParseDExtraHeader_rejectsVoiceType() {
        var packet = Data(count: 56)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        packet[4] = 0x20  // voice, not header
        XCTAssertNil(DVFrame.parseDExtraHeader(packet))
    }

    func testParseDExtraHeader_rejectsTooShort() {
        XCTAssertNil(DVFrame.parseDExtraHeader(Data(count: 40)))
    }

    // MARK: - Serialization

    func testSerializeDExtra_produces27Bytes() {
        let frame = DVFrame(
            streamID: 0x1234,
            frameCounter: 3,
            ambeData: Data(repeating: 0xAA, count: 9),
            slowData: Data(repeating: 0xBB, count: 3)
        )
        let packet = frame.serializeDExtra()
        XCTAssertEqual(packet.count, 27)
    }

    func testSerializeDExtra_roundtrip() {
        let original = DVFrame(
            streamID: 0xABCD,
            frameCounter: 7,
            ambeData: Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8]),
            slowData: Data([0x16, 0x29, 0xF5])
        )
        let packet = original.serializeDExtra()
        let parsed = DVFrame.parseDExtra(packet)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.streamID, original.streamID)
        XCTAssertEqual(parsed?.frameCounter, original.frameCounter)
        XCTAssertEqual(parsed?.ambeData, original.ambeData)
        XCTAssertEqual(parsed?.slowData, original.slowData)
    }

    func testSerializeDExtra_containsMagicAndBandBytes() {
        let frame = DVFrame(
            streamID: 1,
            frameCounter: 0,
            ambeData: Data(count: 9),
            slowData: Data(count: 3)
        )
        let packet = frame.serializeDExtra()
        XCTAssertEqual(packet[0], 0x44) // D
        XCTAssertEqual(packet[1], 0x53) // S
        XCTAssertEqual(packet[2], 0x56) // V
        XCTAssertEqual(packet[3], 0x54) // T
        XCTAssertEqual(packet[4], 0x20) // voice type
        // Unknown byte at offset 8
        XCTAssertEqual(packet[8], 0x20)
        // Band bytes at offsets 9-11
        XCTAssertEqual(packet[9], 0x00)
        XCTAssertEqual(packet[10], 0x02)
        XCTAssertEqual(packet[11], 0x01)
    }

    // MARK: - Header Construction

    func testBuildDExtraHeader_produces56Bytes() {
        let packet = DVFrame.buildDExtraHeader(
            streamID: 0x1234,
            myCallsign: "AI5OS"
        )
        XCTAssertEqual(packet.count, 56)
    }

    func testBuildDExtraHeader_containsMagicAndBandBytes() {
        let packet = DVFrame.buildDExtraHeader(
            streamID: 1,
            myCallsign: "TEST"
        )
        XCTAssertEqual(packet[0], 0x44)
        XCTAssertEqual(packet[1], 0x53)
        XCTAssertEqual(packet[2], 0x56)
        XCTAssertEqual(packet[3], 0x54)
        XCTAssertEqual(packet[4], 0x10) // header type
        XCTAssertEqual(packet[8], 0x20) // unknown[3]
        XCTAssertEqual(packet[9], 0x00) // band[0]
        XCTAssertEqual(packet[10], 0x02) // band[1]
        XCTAssertEqual(packet[11], 0x01) // band[2]
    }

    func testBuildDExtraHeader_roundtrip() {
        let packet = DVFrame.buildDExtraHeader(
            streamID: 0x5678,
            myCallsign: "AI5OS",
            yourCallsign: "CQCQCQ  ",
            rpt1Callsign: "RPT1    ",
            rpt2Callsign: "RPT2    "
        )
        let header = DVFrame.parseDExtraHeader(packet)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.streamID, 0x5678)
        XCTAssertEqual(header?.myCall, "AI5OS")
        XCTAssertEqual(header?.yourCall, "CQCQCQ")
        XCTAssertEqual(header?.rpt1, "RPT1")
        XCTAssertEqual(header?.rpt2, "RPT2")
    }

    func testBuildDExtraHeader_hasCRC() {
        let packet = DVFrame.buildDExtraHeader(
            streamID: 0x1234,
            myCallsign: "AI5OS"
        )
        // CRC at offsets 54-55 should not be zero (computed CRC)
        let crc = UInt16(packet[54]) | (UInt16(packet[55]) << 8)
        XCTAssertNotEqual(crc, 0x0000)
    }

    // MARK: - DPlus Voice Frame

    func testParseDPlus_validVoiceFrame() {
        var packet = Data(count: 29)
        // Length prefix
        packet[0] = 0x1D; packet[1] = 0x80
        // DSVT magic
        packet[2] = 0x44; packet[3] = 0x53; packet[4] = 0x56; packet[5] = 0x54
        // Voice type
        packet[6] = 0x20
        // Unknown + band
        packet[7] = 0x00; packet[8] = 0x00; packet[9] = 0x00; packet[10] = 0x20
        packet[11] = 0x00; packet[12] = 0x02; packet[13] = 0x01
        // Stream ID at offset 14-15
        packet[14] = 0x34; packet[15] = 0x12
        // Frame counter at offset 16
        packet[16] = 0x03
        // AMBE at offset 17
        for i in 0..<9 { packet[17 + i] = UInt8(i + 1) }

        let frame = DVFrame.parseDPlus(packet)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.streamID, 0x1234)
        XCTAssertEqual(frame?.frameCounter, 3)
        XCTAssertEqual(frame?.ambeData[0], 1)
    }

    func testSerializeDPlus_roundtrip() {
        let original = DVFrame(
            streamID: 0xBEEF,
            frameCounter: 12,
            ambeData: Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8]),
            slowData: Data([0x16, 0x29, 0xF5])
        )
        let packet = original.serializeDPlus()
        XCTAssertEqual(packet.count, 29)
        let parsed = DVFrame.parseDPlus(packet)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.streamID, original.streamID)
        XCTAssertEqual(parsed?.frameCounter, original.frameCounter)
        XCTAssertEqual(parsed?.ambeData, original.ambeData)
        XCTAssertEqual(parsed?.slowData, original.slowData)
    }

    func testSerializeDPlus_lastFrame_is32Bytes() {
        let frame = DVFrame(
            streamID: 0x1234,
            frameCounter: 0x45, // frame 5 with last-frame bit
            ambeData: Data(count: 9),
            slowData: Data(count: 3)
        )
        let packet = frame.serializeDPlus()
        XCTAssertEqual(packet.count, 32)
        XCTAssertEqual(packet[0], 0x20) // last-frame length prefix
        XCTAssertEqual(packet[1], 0x80)
        // End pattern bytes
        XCTAssertEqual(packet[29], 0x55)
        XCTAssertEqual(packet[30], 0x55)
        XCTAssertEqual(packet[31], 0x55)
    }

    // MARK: - DPlus Header Frame

    func testBuildDPlusHeader_produces58Bytes() {
        let packet = DVFrame.buildDPlusHeader(
            streamID: 0x1234,
            myCallsign: "AI5OS",
            remoteModule: "A"
        )
        XCTAssertEqual(packet.count, 58)
    }

    func testParseDPlusHeader_roundtrip() {
        let packet = DVFrame.buildDPlusHeader(
            streamID: 0x5678,
            myCallsign: "AI5OS",
            remoteModule: "A",
            yourCallsign: "CQCQCQ  ",
            rpt1Callsign: "RPT1    ",
            rpt2Callsign: "RPT2    "
        )
        let header = DVFrame.parseDPlusHeader(packet)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.streamID, 0x5678)
        XCTAssertEqual(header?.myCall, "AI5OS")
        XCTAssertEqual(header?.yourCall, "CQCQCQ")
        XCTAssertEqual(header?.rpt1, "RPT1")
        XCTAssertEqual(header?.rpt2, "RPT2")
    }

    func testBuildDPlusHeader_usesNoChecksum() {
        let packet = DVFrame.buildDPlusHeader(
            streamID: 0x1234,
            myCallsign: "AI5OS",
            remoteModule: "A"
        )
        // DPlus uses 0xFFFF (no checksum)
        XCTAssertEqual(packet[56], 0xFF)
        XCTAssertEqual(packet[57], 0xFF)
    }
}
