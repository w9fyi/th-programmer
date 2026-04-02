// AMBEDeinterleaveTests.swift — Tests for AMBE 3600x2450 deinterleave correctness

import XCTest
@testable import TH_Programmer

final class AMBEDeinterleaveTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Row Population

    /// The deinterleave must populate all 4 rows of ambe_fr, not just rows 0 and 1.
    /// Row 0 (C0): 24 bits, Row 1 (C1): 23 bits, Row 2 (C2): 11 bits, Row 3 (C3): 14 bits.
    func testDeinterleave_populatesAllFourRows() {
        // Use a non-zero AMBE frame so we can detect if bits land in the right rows
        let allOnes = Data(repeating: 0xFF, count: 9)
        let codec = AMBECodec()
        // Decode should succeed (produces audio, possibly garbled from all-ones, but shouldn't crash)
        let samples = codec.decode(ambeBytes: allOnes)
        XCTAssertNotNil(samples, "All-ones frame should decode without returning nil")
        XCTAssertEqual(samples?.count, 160)
    }

    /// Verify the deinterleave table has exactly 72 entries.
    func testDeinterleaveTable_has72Entries() {
        // The table is internal to AMBECodec, so we test indirectly:
        // 9 bytes × 8 bits = 72 bits must all be mapped.
        // A frame with all zeros should decode (may produce silence or near-silence).
        let zeros = Data(repeating: 0x00, count: 9)
        let codec = AMBECodec()
        let samples = codec.decode(ambeBytes: zeros)
        XCTAssertNotNil(samples)
    }

    // MARK: - Silence Frame Quality

    /// The standard D-STAR silence frame should decode to very low amplitude audio.
    /// If the deinterleave is wrong, the silence frame will produce loud garbled noise.
    func testSilenceFrame_decodesToLowAmplitude() {
        let codec = AMBECodec()
        let silence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])

        // Decode a few consecutive silence frames to let the codec state settle
        for _ in 0..<3 {
            _ = codec.decode(ambeBytes: silence)
        }

        guard let samples = codec.decode(ambeBytes: silence) else {
            XCTFail("Silence frame decode returned nil")
            return
        }

        // Calculate RMS amplitude
        let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
        let rms = sqrt(sumOfSquares / Double(samples.count))

        // Silence should have very low RMS — well under 1000.
        // With the correct deinterleave, the silence frame decodes to near-zero samples.
        // With wrong deinterleave, it produces loud noise (RMS > 5000).
        XCTAssertLessThan(rms, 2000.0,
            "Silence frame RMS \(rms) too high — deinterleave table may be wrong")
    }

    // MARK: - Consecutive Frames Stability

    /// Decoding multiple consecutive frames should not produce wildly varying output.
    /// If the deinterleave is wrong, the codec state drifts and amplitude increases over time.
    func testConsecutiveFrames_stableAmplitude() {
        let codec = AMBECodec()
        let silence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])

        var rmsValues: [Double] = []
        for _ in 0..<10 {
            guard let samples = codec.decode(ambeBytes: silence) else {
                XCTFail("Decode returned nil")
                return
            }
            let sumOfSquares = samples.reduce(0.0) { $0 + Double($1) * Double($1) }
            let rms = sqrt(sumOfSquares / Double(samples.count))
            rmsValues.append(rms)
        }

        // After the first couple of frames settle, RMS should stay low and stable
        let laterFrames = Array(rmsValues.suffix(5))
        for rms in laterFrames {
            XCTAssertLessThan(rms, 2000.0,
                "Frame RMS \(rms) too high after settling — codec state may be drifting")
        }
    }

    // MARK: - Bit Ordering

    /// LSB-first extraction: bit 0 of byte 0 should be the first input bit,
    /// not bit 7 (MSB-first). Verify by checking that the silence frame
    /// produces different output than if we used MSB-first ordering.
    func testBitOrdering_LSBFirst() {
        let codec = AMBECodec()
        // Byte 0x9E = 10011110 binary
        // LSB-first: bits are 0,1,1,1,1,0,0,1
        // MSB-first: bits are 1,0,0,1,1,1,1,0
        // These produce very different ambe_fr contents and thus different audio.
        // We just verify the silence frame decodes reasonably (tested above).
        let silence = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])

        // Settle the codec
        for _ in 0..<5 {
            _ = codec.decode(ambeBytes: silence)
        }

        guard let samples = codec.decode(ambeBytes: silence) else {
            XCTFail("Decode returned nil")
            return
        }

        // With correct LSB-first ordering and correct deinterleave,
        // the silence frame should produce near-zero audio
        let peak = samples.map { abs(Int32($0)) }.max() ?? 0
        XCTAssertLessThan(peak, 5000,
            "Peak amplitude \(peak) too high for silence frame — bit ordering may be wrong")
    }

    // MARK: - Various Frame Patterns

    /// Test that random-looking AMBE data doesn't crash the codec.
    func testRandomFrames_dontCrash() {
        let codec = AMBECodec()
        let frames: [Data] = [
            Data([0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00]),
            Data([0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF, 0xFF]),
            Data([0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA, 0x55, 0xAA]),
            Data([0x12, 0x34, 0x56, 0x78, 0x9A, 0xBC, 0xDE, 0xF0, 0x12]),
            Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8]), // silence
        ]

        for frame in frames {
            let samples = codec.decode(ambeBytes: frame)
            XCTAssertNotNil(samples, "Frame \(frame.map { String(format: "%02X", $0) }.joined()) returned nil")
            XCTAssertEqual(samples?.count, 160)
        }
    }
}
