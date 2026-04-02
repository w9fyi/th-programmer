// DVFrameDCSTests.swift — Tests for DCS and MMDVM parse/serialize methods on DVFrame

import XCTest
@testable import TH_Programmer

final class DVFrameDCSTests: XCTestCase {
    nonisolated deinit {}

    // MARK: - DCS Voice Frame Parsing

    func testParseDCS_validVoiceFrame() {
        var data = Data(count: 100)
        // "0001" tag
        data[0] = 0x30; data[1] = 0x30; data[2] = 0x30; data[3] = 0x31
        // Stream ID
        data[8] = 0x34; data[9] = 0x12
        // Frame counter (non-zero = voice)
        data[14] = 0x05
        // AMBE data
        for i in 0..<9 { data[15 + i] = UInt8(i + 1) }
        // Slow data
        data[24] = 0xAA; data[25] = 0xBB; data[26] = 0xCC

        let frame = DVFrame.parseDCS(data)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.streamID, 0x1234)
        XCTAssertEqual(frame?.frameCounter, 0x05)
        XCTAssertEqual(frame?.ambeData.count, 9)
        XCTAssertEqual(frame?.ambeData[0], 1)
        XCTAssertEqual(frame?.slowData, Data([0xAA, 0xBB, 0xCC]))
    }

    func testParseDCS_rejectsTooShort() {
        let data = Data(count: 50)
        XCTAssertNil(DVFrame.parseDCS(data))
    }

    func testParseDCS_rejectsWrongMagic() {
        var data = Data(count: 100)
        data[0] = 0xFF; data[1] = 0xFF; data[2] = 0xFF; data[3] = 0xFF
        data[14] = 0x05
        XCTAssertNil(DVFrame.parseDCS(data))
    }

    func testParseDCS_rejectsHeaderFrame() {
        var data = Data(count: 100)
        data[0] = 0x30; data[1] = 0x30; data[2] = 0x30; data[3] = 0x31
        data[14] = 0x00  // header frame counter
        XCTAssertNil(DVFrame.parseDCS(data))
    }

    // MARK: - DCS Voice Frame Serialization

    func testSerializeDCS_produces100Bytes() {
        let frame = DVFrame(
            streamID: 0x1234,
            frameCounter: 0x05,
            ambeData: Data(repeating: 0xAB, count: 9),
            slowData: Data(repeating: 0xCD, count: 3)
        )
        let packet = frame.serializeDCS()
        XCTAssertEqual(packet.count, 100)
    }

    func testSerializeDCS_tag() {
        let frame = DVFrame(
            streamID: 0x1234,
            frameCounter: 0x05,
            ambeData: Data(count: 9),
            slowData: Data(count: 3)
        )
        let packet = frame.serializeDCS()
        XCTAssertEqual(packet[0], 0x30)
        XCTAssertEqual(packet[1], 0x30)
        XCTAssertEqual(packet[2], 0x30)
        XCTAssertEqual(packet[3], 0x31)
    }

    func testSerializeDCS_streamID() {
        let frame = DVFrame(
            streamID: 0xABCD,
            frameCounter: 0x01,
            ambeData: Data(count: 9),
            slowData: Data(count: 3)
        )
        let packet = frame.serializeDCS()
        XCTAssertEqual(packet[8], 0xCD)
        XCTAssertEqual(packet[9], 0xAB)
    }

    func testDCSRoundtrip() {
        let original = DVFrame(
            streamID: 0x5678,
            frameCounter: 0x0A,
            ambeData: Data([1, 2, 3, 4, 5, 6, 7, 8, 9]),
            slowData: Data([0x10, 0x20, 0x30])
        )
        let packet = original.serializeDCS()
        let parsed = DVFrame.parseDCS(packet)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.streamID, original.streamID)
        XCTAssertEqual(parsed?.frameCounter, original.frameCounter)
        XCTAssertEqual(parsed?.ambeData, original.ambeData)
        XCTAssertEqual(parsed?.slowData, original.slowData)
    }

    // MARK: - DCS Header

    func testBuildDCSHeader_produces100Bytes() {
        let packet = DVFrame.buildDCSHeader(streamID: 0x1234, myCallsign: "AI5OS")
        XCTAssertEqual(packet.count, 100)
    }

    func testParseDCSHeader_valid() {
        let packet = DVFrame.buildDCSHeader(
            streamID: 0x1234,
            myCallsign: "AI5OS",
            yourCallsign: "CQCQCQ  "
        )
        let header = DVFrame.parseDCSHeader(packet)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.streamID, 0x1234)
        XCTAssertEqual(header?.myCall, "AI5OS")
    }

    // MARK: - MMDVM Conversion

    func testFromMMDVM_valid12BytePayload() {
        var payload = Data(count: 12)
        for i in 0..<9 { payload[i] = UInt8(i + 1) }
        payload[9] = 0xAA; payload[10] = 0xBB; payload[11] = 0xCC

        let frame = DVFrame.fromMMDVM(payload, streamID: 0x1234, frameCounter: 0x05)
        XCTAssertNotNil(frame)
        XCTAssertEqual(frame?.streamID, 0x1234)
        XCTAssertEqual(frame?.frameCounter, 0x05)
        XCTAssertEqual(frame?.ambeData.count, 9)
        XCTAssertEqual(frame?.ambeData[0], 1)
        XCTAssertEqual(frame?.slowData, Data([0xAA, 0xBB, 0xCC]))
    }

    func testFromMMDVM_rejectsTooShort() {
        let payload = Data(count: 8)
        XCTAssertNil(DVFrame.fromMMDVM(payload, streamID: 0x1234, frameCounter: 0))
    }

    func testToMMDVM_producesMMDVMFrame() {
        let frame = DVFrame(
            streamID: 0x1234,
            frameCounter: 0x03,
            ambeData: Data(repeating: 0xAB, count: 9),
            slowData: Data(repeating: 0xCD, count: 3)
        )
        let mmdvmFrame = frame.toMMDVM()
        // MMDVM frame: [0xE0, length, 0x31, 9 AMBE, 3 slow]
        XCTAssertEqual(mmdvmFrame[0], 0xE0)
        XCTAssertEqual(mmdvmFrame[2], MMDVMProtocol.dstarData)
        XCTAssertEqual(mmdvmFrame.count, 15) // 3 header + 12 payload
        // Check AMBE data starts at offset 3
        XCTAssertEqual(mmdvmFrame[3], 0xAB)
        // Check slow data
        XCTAssertEqual(mmdvmFrame[12], 0xCD)
    }

    func testMMDVMRoundtrip() {
        let original = DVFrame(
            streamID: 0x5678,
            frameCounter: 0x07,
            ambeData: Data([9, 8, 7, 6, 5, 4, 3, 2, 1]),
            slowData: Data([0xDE, 0xAD, 0xBE])
        )
        let mmdvmFrame = original.toMMDVM()
        // Extract the payload (skip 3-byte MMDVM header)
        let payload = Data(mmdvmFrame[3...])
        let parsed = DVFrame.fromMMDVM(payload, streamID: original.streamID, frameCounter: original.frameCounter)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.ambeData, original.ambeData)
        XCTAssertEqual(parsed?.slowData, original.slowData)
    }

    // MARK: - MMDVM Header Parsing

    func testHeaderFromMMDVM_valid() {
        // Build an MMDVM header with known callsigns
        let headerFrame = MMDVMProtocol.buildDStarHeader(
            myCallsign: "AI5OS",
            yourCallsign: "CQCQCQ",
            rpt1Callsign: "RPT1TEST",
            rpt2Callsign: "RPT2TEST"
        )
        // Extract payload (skip 3-byte MMDVM header)
        let payload = Data(headerFrame[3...])
        let header = DVFrame.headerFromMMDVM(payload)
        XCTAssertNotNil(header)
        XCTAssertEqual(header?.myCall, "AI5OS")
    }

    func testHeaderFromMMDVM_tooShort() {
        let payload = Data(count: 10)
        XCTAssertNil(DVFrame.headerFromMMDVM(payload))
    }
}
