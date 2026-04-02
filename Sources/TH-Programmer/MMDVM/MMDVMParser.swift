// MMDVMParser.swift — Stateful MMDVM serial frame parser

import Foundation

/// Stateful parser that accumulates serial bytes and emits complete MMDVM frames.
/// Handles partial frames split across serial reads.
final class MMDVMParser: @unchecked Sendable {

    nonisolated deinit {}

    /// Parsed MMDVM frame types.
    enum ParsedFrame: Equatable {
        /// D-STAR header (41-byte payload: 3 flags + 4x8 callsigns + 4 suffix + 2 CRC).
        case dstarHeader(Data)

        /// D-STAR voice data (12-byte payload: 9 AMBE + 3 slow data).
        case dstarVoice(Data)

        /// D-STAR frame lost indicator.
        case dstarLost

        /// D-STAR end-of-transmission.
        case dstarEOT

        /// Firmware version response.
        case version(String)

        /// Modem status response.
        case status(Data)

        /// Acknowledgement.
        case ack

        /// Negative acknowledgement with reason byte.
        case nak(UInt8)

        /// Unknown command.
        case unknown(UInt8, Data)
    }

    private var buffer = Data()

    /// Feed raw serial bytes. Returns zero or more complete parsed frames.
    func feed(_ data: Data) -> [ParsedFrame] {
        buffer.append(data)
        var results: [ParsedFrame] = []

        while buffer.count >= MMDVMProtocol.minFrameSize {
            // Find the 0xE0 marker
            guard let markerIndex = buffer.firstIndex(of: MMDVMProtocol.frameMarker) else {
                buffer.removeAll()
                break
            }

            // Discard any bytes before the marker
            if markerIndex > buffer.startIndex {
                buffer.removeSubrange(buffer.startIndex..<markerIndex)
            }

            guard buffer.count >= MMDVMProtocol.minFrameSize else { break }

            let length = Int(buffer[buffer.startIndex + 1])

            // Sanity check: length must be at least 3
            guard length >= MMDVMProtocol.minFrameSize else {
                // Invalid length — discard this marker and try next
                buffer.removeFirst(1)
                continue
            }

            // Wait for the full frame
            guard buffer.count >= length else { break }

            let frameData = Data(buffer.prefix(length))
            buffer.removeFirst(length)

            let command = frameData[2]
            let payload = frameData.count > 3 ? Data(frameData[3...]) : Data()
            results.append(classify(command: command, payload: payload))
        }

        return results
    }

    /// Reset the parser state, discarding any buffered data.
    func reset() {
        buffer.removeAll()
    }

    // MARK: - Classification

    private func classify(command: UInt8, payload: Data) -> ParsedFrame {
        switch command {
        case MMDVMProtocol.dstarHeader:
            return .dstarHeader(payload)

        case MMDVMProtocol.dstarData:
            return .dstarVoice(payload)

        case MMDVMProtocol.dstarLost:
            return .dstarLost

        case MMDVMProtocol.dstarEOT:
            return .dstarEOT

        case MMDVMProtocol.getVersion:
            // Version response: payload is firmware version string
            let version = payload.isEmpty ? "unknown" : String(data: payload, encoding: .ascii)?.trimmingCharacters(in: .controlCharacters) ?? "unknown"
            return .version(version)

        case MMDVMProtocol.getStatus:
            return .status(payload)

        case MMDVMProtocol.ack:
            return .ack

        case MMDVMProtocol.nak:
            let reason = payload.first ?? 0x00
            return .nak(reason)

        default:
            return .unknown(command, payload)
        }
    }
}
