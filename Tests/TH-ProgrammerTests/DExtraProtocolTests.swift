// DExtraProtocolTests.swift — Tests for DExtra protocol packet construction

import XCTest
@testable import TH_Programmer

final class DExtraProtocolTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Callsign Formatting

    func testPadCallsign_shortCall() {
        XCTAssertEqual(DExtraProtocol.padCallsign("AI5OS"), "AI5OS   ")
    }

    func testPadCallsign_exactLength() {
        XCTAssertEqual(DExtraProtocol.padCallsign("AI5OS/M "), "AI5OS/M ")
    }

    func testPadCallsign_truncatesLong() {
        XCTAssertEqual(DExtraProtocol.padCallsign("ABCDEFGHIJK"), "ABCDEFGH")
    }

    func testPadCallsign_uppercases() {
        XCTAssertEqual(DExtraProtocol.padCallsign("ai5os"), "AI5OS   ")
    }

    func testPadCallsign_empty() {
        XCTAssertEqual(DExtraProtocol.padCallsign(""), "        ")
    }

    func testCallsignBytes_returns8Bytes() {
        let bytes = DExtraProtocol.callsignBytes("AI5OS")
        XCTAssertEqual(bytes.count, 8)
    }

    func testCallsignBytes_spacePadded() {
        let bytes = DExtraProtocol.callsignBytes("W5YI")
        // "W5YI    " in ASCII
        XCTAssertEqual(bytes[0], 0x57) // W
        XCTAssertEqual(bytes[4], 0x20) // space
        XCTAssertEqual(bytes[7], 0x20) // space
    }

    // MARK: - Link Packet

    func testBuildLinkPacket_length() {
        let packet = DExtraProtocol.buildLinkPacket(callsign: "AI5OS", module: " ", remoteModule: "C")
        XCTAssertEqual(packet.count, 11)
    }

    func testBuildLinkPacket_callsignAtStart() {
        let packet = DExtraProtocol.buildLinkPacket(callsign: "AI5OS", module: " ", remoteModule: "C")
        let callBytes = Data("AI5OS   ".utf8)
        XCTAssertEqual(Data(packet.prefix(8)), callBytes)
    }

    func testBuildLinkPacket_moduleAtByte8() {
        let packet = DExtraProtocol.buildLinkPacket(callsign: "AI5OS", module: "X", remoteModule: "C")
        XCTAssertEqual(packet[8], UInt8(ascii: "X"))
    }

    func testBuildLinkPacket_remoteModuleAtByte9() {
        let packet = DExtraProtocol.buildLinkPacket(callsign: "AI5OS", module: " ", remoteModule: "A")
        XCTAssertEqual(packet[9], UInt8(ascii: "A"))
    }

    func testBuildLinkPacket_revisionByte() {
        let packet = DExtraProtocol.buildLinkPacket(callsign: "AI5OS", module: " ", remoteModule: "C")
        XCTAssertEqual(packet[10], 0x0B, "Byte 10 should be 0x0B (revision 1, modern client)")
    }

    // MARK: - Unlink Packet

    func testBuildUnlinkPacket_length() {
        let packet = DExtraProtocol.buildUnlinkPacket(callsign: "AI5OS")
        XCTAssertEqual(packet.count, 11)
    }

    func testBuildUnlinkPacket_spacesAtModuleBytes() {
        let packet = DExtraProtocol.buildUnlinkPacket(callsign: "AI5OS")
        XCTAssertEqual(packet[8], 0x20)  // space
        XCTAssertEqual(packet[9], 0x20)  // space
    }

    // MARK: - Keepalive Packet

    func testBuildKeepalivePacket_length() {
        let packet = DExtraProtocol.buildKeepalivePacket(callsign: "AI5OS")
        XCTAssertEqual(packet.count, 9)
    }

    func testBuildKeepalivePacket_nullTerminated() {
        let packet = DExtraProtocol.buildKeepalivePacket(callsign: "AI5OS")
        XCTAssertEqual(packet[8], 0x00)
    }

    // MARK: - Stream ID

    func testRandomStreamID_nonZero() {
        for _ in 0..<100 {
            XCTAssertGreaterThan(DExtraProtocol.randomStreamID(), 0)
        }
    }

    // MARK: - Hostname

    func testHostname_REF() {
        XCTAssertEqual(DExtraProtocol.hostname(type: "REF", number: 1), "ref001.dstargateway.org")
    }

    func testHostname_XRF() {
        XCTAssertEqual(DExtraProtocol.hostname(type: "XRF", number: 12), "xrf012.dstargateway.org")
    }

    func testHostname_DCS() {
        XCTAssertEqual(DExtraProtocol.hostname(type: "DCS", number: 999), "dcs999.dstargateway.org")
    }

    func testHostname_clampsLow() {
        XCTAssertEqual(DExtraProtocol.hostname(type: "REF", number: 0), "ref001.dstargateway.org")
    }

    func testHostname_clampsHigh() {
        XCTAssertEqual(DExtraProtocol.hostname(type: "REF", number: 1500), "ref999.dstargateway.org")
    }

    // MARK: - Packet Identification

    func testIdentifyPacket_voiceFrame() {
        var packet = Data(count: 27)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        packet[4] = 0x20
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .voice)
    }

    func testIdentifyPacket_headerFrame() {
        var packet = Data(count: 56)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54
        packet[4] = 0x10
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .header)
    }

    func testIdentifyPacket_linkNak_11bytes_lastByteZero() {
        var packet = Data(count: 11)
        // 11 bytes with non-space at bytes 8-9, last byte 0x00 = NAK
        packet[8] = 0x41  // 'A'
        packet[9] = 0x42  // 'B'
        // packet[10] is already 0x00
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .linkNak)
    }

    func testIdentifyPacket_linkAck_11bytes_lastByteNonZero() {
        var packet = Data(count: 11)
        packet[8] = 0x41  // 'A'
        packet[9] = 0x42  // 'B'
        packet[10] = 0x41 // non-zero = ACK
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .linkAck)
    }

    func testIdentifyPacket_empty() {
        XCTAssertEqual(DExtraProtocol.identifyPacket(Data()), .unknown)
    }

    // MARK: - Constants

    func testSilenceAMBE_is9Bytes() {
        XCTAssertEqual(DExtraProtocol.silenceAMBE.count, 9)
    }

    func testFillerSlowData_is3Bytes() {
        XCTAssertEqual(DExtraProtocol.fillerSlowData.count, 3)
    }

    func testFramesPerSuperframe_is21() {
        XCTAssertEqual(DExtraProtocol.framesPerSuperframe, 21)
    }

    func testPort_is30001() {
        XCTAssertEqual(DExtraProtocol.port, 30001)
    }
}
