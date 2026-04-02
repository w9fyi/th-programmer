// AMBECodec.swift — Swift wrapper around mbelib for AMBE 3600x2450 (D-STAR) codec

import Foundation
import mbelib

/// Decodes and encodes AMBE 3600x2450 voice frames used by D-STAR.
/// Each frame is 9 bytes (72 bits) of AMBE data → 160 PCM samples (20ms @ 8kHz).
final class AMBECodec: @unchecked Sendable {

    nonisolated deinit {}

    private var curMp = mbe_parms()
    private var prevMp = mbe_parms()
    private var prevMpEnhanced = mbe_parms()

    /// Quality setting for mbelib synthesis (3 = best, 1 = fastest).
    private let uvQuality: Int32 = 3

    init() {
        mbe_initMbeParms(&curMp, &prevMp, &prevMpEnhanced)
    }

    /// Reset codec state (call between transmissions).
    func reset() {
        mbe_initMbeParms(&curMp, &prevMp, &prevMpEnhanced)
    }

    // MARK: - Decode (AMBE → PCM)

    /// Decode a 9-byte AMBE 3600x2450 frame into 160 Int16 PCM samples (20ms @ 8kHz).
    /// Returns nil if the input is not exactly 9 bytes.
    func decode(ambeBytes: Data) -> [Int16]? {
        guard ambeBytes.count == 9 else { return nil }

        // Convert 9 bytes (72 bits) into the ambe_fr[4][24] bit matrix
        var ambe_fr = Array(repeating: Array(repeating: CChar(0), count: 24), count: 4)
        var ambe_d = Array(repeating: CChar(0), count: 49)

        // Deinterleave 72 bits into the 4x24 frame matrix
        let bytes = Array(ambeBytes)
        deinterleaveAmbe3600x2450(bytes: bytes, ambe_fr: &ambe_fr)

        // Decode using mbelib
        var aout_buf = [Int16](repeating: 0, count: 160)
        var errs: Int32 = 0
        var errs2: Int32 = 0
        var err_str = [CChar](repeating: 0, count: 64)

        // Flatten ambe_fr[4][24] into contiguous char[96] for mbelib
        var flatFr = [CChar](repeating: 0, count: 96)
        for i in 0..<4 {
            for j in 0..<24 {
                flatFr[i * 24 + j] = ambe_fr[i][j]
            }
        }

        flatFr.withUnsafeMutableBufferPointer { frPtr in
            ambe_d.withUnsafeMutableBufferPointer { dPtr in
                aout_buf.withUnsafeMutableBufferPointer { outPtr in
                    err_str.withUnsafeMutableBufferPointer { errPtr in
                        // Cast flat array to the expected char(*)[24] type
                        let fr2d = UnsafeMutableRawPointer(frPtr.baseAddress!)
                            .bindMemory(to: (CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                             CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar,
                                             CChar, CChar, CChar, CChar, CChar, CChar, CChar, CChar).self,
                                        capacity: 4)
                        mbe_processAmbe3600x2450Frame(
                            outPtr.baseAddress!, &errs, &errs2,
                            errPtr.baseAddress!,
                            fr2d, dPtr.baseAddress!,
                            &curMp, &prevMp, &prevMpEnhanced,
                            uvQuality
                        )
                    }
                }
            }
        }

        return aout_buf
    }

    /// Generate 160 samples of silence.
    func decodeSilence() -> [Int16] {
        var aout_buf = [Int16](repeating: 0, count: 160)
        aout_buf.withUnsafeMutableBufferPointer { ptr in
            mbe_synthesizeSilence(ptr.baseAddress!)
        }
        return aout_buf
    }

    // MARK: - Bit Deinterleaving

    /// DSD dW table — row assignments for each of the 72 input bits.
    /// From szechyjs/dsd include/dstar_const.h (canonical D-STAR AMBE 3600x2450 deinterleave).
    /// Populates all 4 rows: C0(24 bits), C1(23 bits), C2(11 bits), C3(14 bits).
    private static let dW: [Int] = [
        0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
        3, 2, 1, 1, 3, 2, 1, 1, 0, 0, 3, 2,
        0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
        3, 2, 1, 1, 3, 2, 1, 1, 0, 0, 3, 2,
        0, 0, 3, 2, 1, 1, 0, 0, 1, 1, 0, 0,
        3, 2, 1, 1, 3, 3, 2, 1, 0, 0, 3, 3
    ]

    /// DSD dX table — column assignments for each of the 72 input bits.
    private static let dX: [Int] = [
        10, 22, 11,  9, 10, 22, 11, 23,  8, 20,  9, 21,
        10,  8,  9, 21,  8,  6,  7, 19,  8, 20,  9,  7,
         6, 18,  7,  5,  6, 18,  7, 19,  4, 16,  5, 17,
         6,  4,  5, 17,  4,  2,  3, 15,  4, 16,  5,  3,
         2, 14,  3,  1,  2, 14,  3, 15,  0, 12,  1, 13,
         2,  0,  1, 13,  0, 12, 10, 11,  0, 12,  1, 13
    ]

    /// Deinterleave 9 bytes (72 bits) of AMBE data into the ambe_fr[4][24] bit matrix.
    /// Uses the DSD dW/dX tables and LSB-first bit extraction (D-STAR transmits LSB-first).
    private func deinterleaveAmbe3600x2450(bytes: [UInt8], ambe_fr: inout [[CChar]]) {
        for bitIndex in 0..<72 {
            let byteIndex = bitIndex / 8
            let bitOffset = bitIndex % 8  // LSB-first (D-STAR bit ordering)
            let bit = CChar((bytes[byteIndex] >> bitOffset) & 1)
            let row = Self.dW[bitIndex]
            let col = Self.dX[bitIndex]
            ambe_fr[row][col] = bit
        }
    }

    // MARK: - Encode (PCM → AMBE)

    /// Encode 160 Int16 PCM samples into a 9-byte AMBE 3600x2450 frame.
    /// Note: mbelib does not have a native encoder. This produces a basic vocoder
    /// approximation by analyzing the PCM and selecting the closest AMBE parameters.
    /// For MVP, we use a silence frame when encoding is needed, and will improve later.
    func encode(pcm: [Int16]) -> Data {
        // mbelib is decode-only for AMBE. For TX, we need an encoder.
        // MVP approach: return silence AMBE frame. Full encoder is Phase 2+ work.
        // The standard AMBE silence frame for D-STAR:
        return Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])
    }
}
