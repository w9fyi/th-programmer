// SlowDataDecoderTests.swift — Tests for D-STAR slow data decoding

import XCTest
@testable import TH_Programmer

final class SlowDataDecoderTests: XCTestCase {
    nonisolated deinit {}

    private var decoder: SlowDataDecoder!

    override func setUp() {
        super.setUp()
        decoder = SlowDataDecoder()
    }

    override func tearDown() {
        decoder = nil
        super.tearDown()
    }

    // MARK: - Basic Operation

    func testFeed_returnsNilBeforeSuperframeComplete() {
        let slowData = Data([0x16, 0x29, 0xF5])  // filler
        for i in 0..<20 {
            let result = decoder.feed(slowData: slowData, frameCounter: UInt8(i))
            XCTAssertNil(result, "Should not decode until frame 21")
        }
    }

    func testFeed_returnsDecodedDataAtSuperframeBoundary() {
        let slowData = Data([0x16, 0x29, 0xF5])  // filler
        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            result = decoder.feed(slowData: slowData, frameCounter: UInt8(i))
        }
        XCTAssertNotNil(result, "Should decode at frame 21")
    }

    func testReset_clearsState() {
        let slowData = Data([0x16, 0x29, 0xF5])
        // Feed 10 frames
        for i in 0..<10 {
            _ = decoder.feed(slowData: slowData, frameCounter: UInt8(i))
        }
        decoder.reset()
        // After reset, feeding 21 frames from 0 should produce a result
        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            result = decoder.feed(slowData: slowData, frameCounter: UInt8(i))
        }
        XCTAssertNotNil(result)
    }

    func testFrameCounter0_resetsAccumulation() {
        let slowData = Data([0x16, 0x29, 0xF5])
        // Feed 15 frames
        for i in 0..<15 {
            _ = decoder.feed(slowData: slowData, frameCounter: UInt8(i))
        }
        // Start new superframe at counter 0 — resets
        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            result = decoder.feed(slowData: slowData, frameCounter: UInt8(i))
        }
        XCTAssertNotNil(result)
    }

    // MARK: - Text Message Decoding

    func testDecode_textMessage() {
        // Build a superframe with a text message block in the first 6 bytes
        // Type 0x40 + "HELLO" (5 ASCII bytes)
        var allSlowData = Data()
        allSlowData.append(contentsOf: [0x40, 0x48, 0x45, 0x4C, 0x4C, 0x4F])  // "HELLO"
        // Fill remaining frames with filler
        let fillerPerFrame = Data([0x16, 0x29, 0xF5])
        let totalBytes = 21 * 3  // 63 bytes
        while allSlowData.count < totalBytes {
            allSlowData.append(contentsOf: fillerPerFrame)
        }

        // Feed as 3-byte chunks
        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            let start = i * 3
            let chunk = allSlowData[start..<start + 3]
            result = decoder.feed(slowData: Data(chunk), frameCounter: UInt8(i))
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.textMessage, "HELLO")
    }

    func testDecode_multiBlockTextMessage() {
        // Two text blocks: 0x40 + "HELLO" then 0x41 + " WRLD"
        var allSlowData = Data()
        allSlowData.append(contentsOf: [0x40, 0x48, 0x45, 0x4C, 0x4C, 0x4F])  // "HELLO"
        allSlowData.append(contentsOf: [0x41, 0x20, 0x57, 0x52, 0x4C, 0x44])  // " WRLD"
        let fillerPerFrame = Data([0x16, 0x29, 0xF5])
        let totalBytes = 21 * 3
        while allSlowData.count < totalBytes {
            allSlowData.append(contentsOf: fillerPerFrame)
        }

        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            let start = i * 3
            let chunk = allSlowData[start..<start + 3]
            result = decoder.feed(slowData: Data(chunk), frameCounter: UInt8(i))
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.textMessage, "HELLO WRLD")
    }

    // MARK: - GPS Decoding

    func testDecode_gpsPosition() {
        // GPS block: 0x30 + "12345"
        var allSlowData = Data()
        allSlowData.append(contentsOf: [0x30, 0x31, 0x32, 0x33, 0x34, 0x35])  // "12345"
        let fillerPerFrame = Data([0x16, 0x29, 0xF5])
        let totalBytes = 21 * 3
        while allSlowData.count < totalBytes {
            allSlowData.append(contentsOf: fillerPerFrame)
        }

        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            let start = i * 3
            let chunk = allSlowData[start..<start + 3]
            result = decoder.feed(slowData: Data(chunk), frameCounter: UInt8(i))
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.gpsPosition, "12345")
    }

    // MARK: - Filler Only

    func testDecode_fillerOnly_emptyResult() {
        let filler = Data([0x16, 0x29, 0xF5])
        var result: SlowDataDecoder.DecodedData?
        for i in 0..<21 {
            result = decoder.feed(slowData: filler, frameCounter: UInt8(i))
        }

        XCTAssertNotNil(result)
        XCTAssertEqual(result?.textMessage, "")
        XCTAssertEqual(result?.gpsPosition, "")
    }

    // MARK: - DecodedData Equatable

    func testDecodedData_equatable() {
        let a = SlowDataDecoder.DecodedData(textMessage: "Hi", gpsPosition: "")
        let b = SlowDataDecoder.DecodedData(textMessage: "Hi", gpsPosition: "")
        let c = SlowDataDecoder.DecodedData(textMessage: "Bye", gpsPosition: "")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }
}
