// MMDVMProtocol.swift — MMDVM serial protocol constants and frame builders

import Foundation

/// MMDVM (Multi-Mode Digital Voice Modem) serial protocol constants.
/// The TH-D75 speaks this protocol in terminal mode (Menu 650).
///
/// Frame format: [0xE0] [length] [command] [payload...]
/// Length includes the marker, length, and command bytes.
enum MMDVMProtocol {

    /// Frame start marker byte.
    static let frameMarker: UInt8 = 0xE0

    /// Minimum frame size (marker + length + command).
    static let minFrameSize = 3

    // MARK: - Host → Modem Commands

    /// Get firmware version.
    static let getVersion: UInt8 = 0x00

    /// Get modem status.
    static let getStatus: UInt8 = 0x01

    /// Set modem configuration.
    static let setConfig: UInt8 = 0x02

    /// Set modem mode.
    static let setMode: UInt8 = 0x03

    // MARK: - D-STAR Frame Commands

    /// D-STAR header frame (41 bytes of D-STAR header data).
    static let dstarHeader: UInt8 = 0x30

    /// D-STAR voice data frame (9 AMBE + 3 slow data = 12 bytes).
    static let dstarData: UInt8 = 0x31

    /// D-STAR frame lost indicator.
    static let dstarLost: UInt8 = 0x32

    /// D-STAR end-of-transmission.
    static let dstarEOT: UInt8 = 0x33

    // MARK: - Modem → Host Responses

    /// Acknowledgement.
    static let ack: UInt8 = 0x70

    /// Negative acknowledgement (followed by reason byte).
    static let nak: UInt8 = 0x7F

    // MARK: - Configuration

    /// Build a Set Config frame that enables D-STAR mode.
    /// Based on MMDVMHost's CModem::setConfig.
    /// Payload layout (after command byte):
    ///   Byte 0 (flags1): bit0=rxInvert, bit1=txInvert, bit2=pttInvert, bit7=simplex
    ///   Byte 1 (modes):  bit0=D-STAR, bit1=DMR, bit2=YSF, bit3=P25, bit4=NXDN
    ///   Bytes 2+: TX delay, mode-specific params (zeros = defaults)
    static func buildSetConfig() -> Data {
        var payload = Data(count: 16)
        payload[0] = 0x80  // flags1: simplex mode (bit 7), no inversions
        payload[1] = 0x01  // modes: D-STAR enabled (bit 0)
        // Remaining bytes are TX delay, frequency offsets, etc. — zeros = defaults
        return buildFrame(command: setConfig, payload: payload)
    }

    /// Build a Set Mode frame to activate D-STAR mode.
    /// Mode byte: 0x00 = idle, 0x01 = D-STAR, 0x02 = DMR, etc.
    static func buildSetMode(mode: UInt8 = 0x01) -> Data {
        buildFrame(command: setMode, payload: Data([mode]))
    }

    // MARK: - Frame Builders

    /// Build a complete MMDVM frame: [0xE0, length, command, ...payload]
    static func buildFrame(command: UInt8, payload: Data = Data()) -> Data {
        let length = UInt8(3 + payload.count)
        var frame = Data(capacity: Int(length))
        frame.append(frameMarker)
        frame.append(length)
        frame.append(command)
        frame.append(payload)
        return frame
    }

    /// Build a Get Version probe: [0xE0, 0x03, 0x00]
    static func buildGetVersion() -> Data {
        buildFrame(command: getVersion)
    }

    /// Build a Get Status probe: [0xE0, 0x03, 0x01]
    static func buildGetStatus() -> Data {
        buildFrame(command: getStatus)
    }

    /// Build a D-STAR voice data frame for sending to the modem.
    /// Payload is 12 bytes: 9 AMBE + 3 slow data.
    static func buildDStarData(ambe: Data, slowData: Data) -> Data {
        var payload = Data(capacity: 12)
        payload.append(ambe.prefix(9))
        if ambe.count < 9 {
            payload.append(Data(count: 9 - ambe.count))
        }
        payload.append(slowData.prefix(3))
        if slowData.count < 3 {
            payload.append(Data(count: 3 - slowData.count))
        }
        return buildFrame(command: dstarData, payload: payload)
    }

    /// Build a D-STAR EOT frame.
    static func buildDStarEOT() -> Data {
        buildFrame(command: dstarEOT)
    }

    /// Build a D-STAR header frame from callsign fields.
    /// The header payload is 41 bytes of D-STAR header data.
    static func buildDStarHeader(
        myCallsign: String,
        yourCallsign: String = "CQCQCQ  ",
        rpt1Callsign: String = "        ",
        rpt2Callsign: String = "        "
    ) -> Data {
        var payload = Data(count: 41)

        // Bytes 0-2: flag bytes
        payload[0] = 0x00
        payload[1] = 0x00
        payload[2] = 0x00

        // Bytes 3-10: RPT2 callsign (8 bytes)
        writeCallsign(rpt2Callsign, to: &payload, offset: 3)
        // Bytes 11-18: RPT1 callsign (8 bytes)
        writeCallsign(rpt1Callsign, to: &payload, offset: 11)
        // Bytes 19-26: YOUR callsign (8 bytes)
        writeCallsign(yourCallsign, to: &payload, offset: 19)
        // Bytes 27-34: MY callsign (8 bytes)
        writeCallsign(myCallsign, to: &payload, offset: 27)
        // Bytes 35-38: MY suffix (4 bytes)
        payload[35] = 0x20
        payload[36] = 0x20
        payload[37] = 0x20
        payload[38] = 0x20

        // Bytes 39-40: CRC-CCITT over bytes 0-38
        let crc = DVFrame.dstarCRC(data: payload, from: 0, count: 39)
        payload[39] = UInt8(crc & 0xFF)
        payload[40] = UInt8((crc >> 8) & 0xFF)

        return buildFrame(command: dstarHeader, payload: payload)
    }

    // MARK: - Helpers

    private static func writeCallsign(_ call: String, to data: inout Data, offset: Int) {
        let padded = call.padding(toLength: 8, withPad: " ", startingAt: 0)
        for (i, byte) in padded.utf8.prefix(8).enumerated() {
            data[offset + i] = byte
        }
    }
}
