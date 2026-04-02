// SlowDataDecoder.swift — D-STAR slow data accumulator and decoder

import Foundation

/// Accumulates and decodes D-STAR slow data from voice frame payloads.
///
/// D-STAR slow data: 3 bytes per voice frame × 21 frames per superframe = 63 bytes.
/// Contains text messages (type 0x40–0x43) and GPS position data (type 0x30–0x35).
final class SlowDataDecoder: @unchecked Sendable {

    nonisolated deinit {}

    /// Decoded slow data from a complete superframe.
    struct DecodedData: Equatable, Sendable {
        var textMessage: String = ""
        var gpsPosition: String = ""
    }

    /// Accumulated slow data bytes across a superframe.
    private var buffer = Data()

    /// Number of frames fed in the current superframe.
    private var frameCount: Int = 0

    /// Frames per superframe (0–20 = 21 frames).
    private let framesPerSuperframe = 21

    /// Feed 3 bytes of slow data from a voice frame.
    /// Returns decoded data when a full superframe has been accumulated, nil otherwise.
    func feed(slowData: Data, frameCounter: UInt8) -> DecodedData? {
        // Detect superframe boundary reset
        if frameCounter == 0 {
            buffer.removeAll(keepingCapacity: true)
            frameCount = 0
        }

        buffer.append(slowData)
        frameCount += 1

        // Decode when we have a full superframe
        if frameCount >= framesPerSuperframe {
            let result = decode(buffer)
            buffer.removeAll(keepingCapacity: true)
            frameCount = 0
            return result
        }

        return nil
    }

    /// Reset the decoder state (e.g., on new stream ID).
    func reset() {
        buffer.removeAll(keepingCapacity: true)
        frameCount = 0
    }

    // MARK: - Decoding

    /// Decode accumulated slow data bytes into text message and GPS fields.
    private func decode(_ data: Data) -> DecodedData {
        var result = DecodedData()
        var offset = 0

        while offset < data.count {
            let byte = data[offset]
            let typeNibble = byte & 0xF0

            switch typeNibble {
            case 0x40:
                // Text message: 0x40–0x43, each carries up to 5 ASCII bytes
                let textBytes = extractBlock(from: data, at: offset)
                let text = String(bytes: textBytes, encoding: .ascii) ?? ""
                result.textMessage += text.replacingOccurrences(of: "\u{66}", with: "")  // strip filler 0x66
                offset += 6  // type byte + 5 data bytes

            case 0x30:
                // GPS data: 0x30–0x35, each carries up to 5 ASCII bytes
                let gpsBytes = extractBlock(from: data, at: offset)
                let gps = String(bytes: gpsBytes, encoding: .ascii) ?? ""
                result.gpsPosition += gps
                offset += 6

            default:
                // Skip unrecognized or filler blocks
                offset += 1
            }
        }

        // Clean up decoded text
        result.textMessage = result.textMessage
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .whitespaces)
        result.gpsPosition = result.gpsPosition
            .trimmingCharacters(in: .controlCharacters)
            .trimmingCharacters(in: .whitespaces)

        return result
    }

    /// Extract up to 5 data bytes following a type byte in a slow data block.
    private func extractBlock(from data: Data, at offset: Int) -> [UInt8] {
        var bytes: [UInt8] = []
        let start = offset + 1  // skip the type byte
        let end = Swift.min(start + 5, data.count)
        for i in start..<end {
            let b = data[i]
            if b != 0x66 && b >= 0x20 && b < 0x7F {  // printable ASCII, not filler
                bytes.append(b)
            }
        }
        return bytes
    }
}
