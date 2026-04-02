// AMBECodecTests.swift — Tests for AMBE 3600x2450 codec wrapper

import XCTest
@testable import TH_Programmer

final class AMBECodecTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Decode

    func testDecode_silenceFrame_produces160Samples() {
        let codec = AMBECodec()
        let silence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])
        let samples = codec.decode(ambeBytes: silence)
        XCTAssertNotNil(samples)
        XCTAssertEqual(samples?.count, 160)
    }

    func testDecode_zeroFrame_produces160Samples() {
        let codec = AMBECodec()
        let zeros = Data(repeating: 0x00, count: 9)
        let samples = codec.decode(ambeBytes: zeros)
        XCTAssertNotNil(samples)
        XCTAssertEqual(samples?.count, 160)
    }

    func testDecode_rejectsWrongSize() {
        let codec = AMBECodec()
        XCTAssertNil(codec.decode(ambeBytes: Data(repeating: 0, count: 8)))
        XCTAssertNil(codec.decode(ambeBytes: Data(repeating: 0, count: 10)))
        XCTAssertNil(codec.decode(ambeBytes: Data()))
    }

    func testDecode_samplesInInt16Range() {
        let codec = AMBECodec()
        let silence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])
        guard let samples = codec.decode(ambeBytes: silence) else {
            XCTFail("Decode returned nil")
            return
        }
        for sample in samples {
            XCTAssertGreaterThanOrEqual(sample, Int16.min)
            XCTAssertLessThanOrEqual(sample, Int16.max)
        }
    }

    func testDecodeSilence_produces160Samples() {
        let codec = AMBECodec()
        let samples = codec.decodeSilence()
        XCTAssertEqual(samples.count, 160)
    }

    func testReset_doesNotCrash() {
        let codec = AMBECodec()
        let silence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])
        _ = codec.decode(ambeBytes: silence)
        codec.reset()
        let after = codec.decode(ambeBytes: silence)
        XCTAssertNotNil(after)
        XCTAssertEqual(after?.count, 160)
    }

    // MARK: - Encode (MVP returns silence)

    func testEncode_returns9Bytes() {
        let codec = AMBECodec()
        let pcm = [Int16](repeating: 0, count: 160)
        let encoded = codec.encode(pcm: pcm)
        XCTAssertEqual(encoded.count, 9)
    }

    func testEncode_returnsSilenceFrame() {
        let codec = AMBECodec()
        let pcm = [Int16](repeating: 100, count: 160)
        let encoded = codec.encode(pcm: pcm)
        let expectedSilence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])
        XCTAssertEqual(encoded, expectedSilence)
    }
}
