// MMDVMParserTests.swift — Tests for the MMDVM serial frame parser

import XCTest
@testable import TH_Programmer

final class MMDVMParserTests: XCTestCase {
    nonisolated deinit {}

    private var parser: MMDVMParser!

    override func setUp() {
        super.setUp()
        parser = MMDVMParser()
    }

    override func tearDown() {
        parser = nil
        super.tearDown()
    }

    // MARK: - Frame Assembly

    func testParseSingleCompleteFrame() {
        // [0xE0, 0x04, 0x70, 0x00] — ACK with 1-byte payload
        let data = Data([0xE0, 0x04, 0x70, 0x00])
        let frames = parser.feed(data)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .ack)
    }

    func testParseTwoFramesInOneChunk() {
        // Two ACK frames back to back
        let data = Data([0xE0, 0x03, 0x70, 0xE0, 0x03, 0x70])
        let frames = parser.feed(data)
        XCTAssertEqual(frames.count, 2)
        XCTAssertEqual(frames[0], .ack)
        XCTAssertEqual(frames[1], .ack)
    }

    func testParseFrameSplitAcrossChunks() {
        // Send first 2 bytes, then remaining byte
        let frames1 = parser.feed(Data([0xE0, 0x03]))
        XCTAssertEqual(frames1.count, 0)

        let frames2 = parser.feed(Data([0x70]))
        XCTAssertEqual(frames2.count, 1)
        XCTAssertEqual(frames2[0], .ack)
    }

    func testDiscardsBytesBeforeMarker() {
        // Garbage bytes before a valid frame
        let data = Data([0xFF, 0xAA, 0x55, 0xE0, 0x03, 0x70])
        let frames = parser.feed(data)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .ack)
    }

    func testEmptyInput() {
        let frames = parser.feed(Data())
        XCTAssertEqual(frames.count, 0)
    }

    func testReset() {
        // Feed partial frame
        _ = parser.feed(Data([0xE0, 0x03]))
        parser.reset()
        // Feed a complete different frame
        let frames = parser.feed(Data([0xE0, 0x03, 0x70]))
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .ack)
    }

    // MARK: - D-STAR Frame Types

    func testDStarHeader() {
        var payload = Data(count: 41)
        payload[0] = 0x00 // flags
        // Write "AI5OS   " at offset 27 (MY callsign)
        let cs = "AI5OS   ".utf8
        for (i, byte) in cs.enumerated() {
            payload[27 + i] = byte
        }

        let frame = MMDVMProtocol.buildFrame(command: MMDVMProtocol.dstarHeader, payload: payload)
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        if case .dstarHeader(let data) = frames[0] {
            XCTAssertEqual(data.count, 41)
        } else {
            XCTFail("Expected dstarHeader")
        }
    }

    func testDStarVoice_12BytePayload() {
        var payload = Data(count: 12)
        for i in 0..<9 { payload[i] = UInt8(i) }
        payload[9] = 0xAA; payload[10] = 0xBB; payload[11] = 0xCC

        let frame = MMDVMProtocol.buildFrame(command: MMDVMProtocol.dstarData, payload: payload)
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        if case .dstarVoice(let data) = frames[0] {
            XCTAssertEqual(data.count, 12)
            XCTAssertEqual(data[0], 0)
            XCTAssertEqual(data[9], 0xAA)
        } else {
            XCTFail("Expected dstarVoice")
        }
    }

    func testDStarEOT() {
        let frame = MMDVMProtocol.buildDStarEOT()
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .dstarEOT)
    }

    func testDStarLost() {
        let frame = MMDVMProtocol.buildFrame(command: MMDVMProtocol.dstarLost)
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .dstarLost)
    }

    // MARK: - Host Commands

    func testGetVersionResponse() {
        let version = "MMDVM 20240101"
        let payload = Data(version.utf8)
        let frame = MMDVMProtocol.buildFrame(command: MMDVMProtocol.getVersion, payload: payload)
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        if case .version(let v) = frames[0] {
            XCTAssertEqual(v, "MMDVM 20240101")
        } else {
            XCTFail("Expected version")
        }
    }

    func testAck() {
        let frame = MMDVMProtocol.buildFrame(command: MMDVMProtocol.ack)
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .ack)
    }

    func testNak() {
        let frame = MMDVMProtocol.buildFrame(command: MMDVMProtocol.nak, payload: Data([0x42]))
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .nak(0x42))
    }

    // MARK: - Edge Cases

    func testPartialFrameWaitsForMore() {
        // Length says 10 bytes but only 5 available
        let partial = Data([0xE0, 0x0A, 0x31, 0x01, 0x02])
        let frames = parser.feed(partial)
        XCTAssertEqual(frames.count, 0)

        // Send remaining bytes
        let rest = Data([0x03, 0x04, 0x05, 0x06, 0x07])
        let frames2 = parser.feed(rest)
        XCTAssertEqual(frames2.count, 1)
    }

    func testInvalidLengthByte_discards() {
        // Length < 3 is invalid — should discard marker and find next
        let data = Data([0xE0, 0x01, 0xFF, 0xE0, 0x03, 0x70])
        let frames = parser.feed(data)
        // After discarding the invalid frame marker, should find the ACK
        XCTAssertEqual(frames.count, 1)
        XCTAssertEqual(frames[0], .ack)
    }

    func testUnknownCommand() {
        let frame = MMDVMProtocol.buildFrame(command: 0xFE, payload: Data([0x01, 0x02]))
        let frames = parser.feed(frame)
        XCTAssertEqual(frames.count, 1)
        if case .unknown(let cmd, let payload) = frames[0] {
            XCTAssertEqual(cmd, 0xFE)
            XCTAssertEqual(payload, Data([0x01, 0x02]))
        } else {
            XCTFail("Expected unknown")
        }
    }
}
