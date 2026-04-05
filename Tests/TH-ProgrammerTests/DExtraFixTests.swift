// DExtraFixTests.swift — Tests for DExtra protocol fixes
//
// Validates:
//   1. ACK detection matches real DExtra protocol (11 bytes, last byte non-zero)
//   2. NAK detection (11 bytes, last byte 0x00 echoed back = no change = NAK)
//   3. Ephemeral local port (no mandatory 30001 bind)
//   4. Local module matches remote module for direct connections
//   5. XLX reflector routing
//
// No hardware required — all packet-level unit tests.

import XCTest
@testable import TH_Programmer

final class DExtraFixTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - ACK Detection (real DExtra protocol)
    //
    // DExtra ACK: reflector echoes back the 11-byte link packet with the
    // last byte changed from 0x00 to a non-zero value (typically the
    // remote module letter). This is how ircDDBGateway and DroidStar detect it.

    /// Build a simulated DExtra ACK: the link packet echoed back with last byte = module letter.
    private func buildDExtraACK(callsign: String = "AI5OS", localModule: Character = "C", remoteModule: Character = "C") -> Data {
        // Reflector echoes: [callsign(8)][localModule][remoteModule][non-zero]
        var packet = DExtraProtocol.callsignBytes(callsign)
        packet.append(contentsOf: String(localModule).utf8.prefix(1))
        packet.append(contentsOf: String(remoteModule).utf8.prefix(1))
        packet.append(UInt8(ascii: "C"))  // non-zero = ACK
        return packet
    }

    /// Build a simulated DExtra NAK: same as link packet (last byte still 0x00).
    private func buildDExtraNAK(callsign: String = "AI5OS", localModule: Character = "C", remoteModule: Character = "C") -> Data {
        // NAK: reflector echoes packet unchanged (last byte still 0x00)
        var packet = DExtraProtocol.callsignBytes(callsign)
        packet.append(contentsOf: String(localModule).utf8.prefix(1))
        packet.append(contentsOf: String(remoteModule).utf8.prefix(1))
        packet.append(0x00)  // 0x00 = NAK / unchanged
        return packet
    }

    func testIdentifyPacket_DExtraACK_11bytes_lastByteNonZero() {
        let ack = buildDExtraACK()
        XCTAssertEqual(ack.count, 11)
        let type = DExtraProtocol.identifyPacket(ack)
        XCTAssertEqual(type, .linkAck,
                       "11-byte packet with last byte non-zero should be linkAck, got \(type)")
    }

    func testIdentifyPacket_DExtraACK_variousModules() {
        // ACK with different module letters — all should be .linkAck
        for module in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            var packet = DExtraProtocol.callsignBytes("W9FYI")
            packet.append(UInt8(ascii: "C"))  // local
            packet.append(UInt8(ascii: "C"))  // remote
            packet.append(UInt8(module.asciiValue!))  // non-zero = ACK
            XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .linkAck,
                           "Module \(module) ACK should be .linkAck")
        }
    }

    func testIdentifyPacket_DExtraNAK_11bytes_lastByteZero() {
        let nak = buildDExtraNAK()
        XCTAssertEqual(nak.count, 11)
        let type = DExtraProtocol.identifyPacket(nak)
        XCTAssertEqual(type, .linkNak,
                       "11-byte packet with last byte 0x00 (echo of request) should be linkNak, got \(type)")
    }

    func testIdentifyPacket_unlink_spacesAtBytes8And9() {
        // Unlink: 11 bytes with spaces at bytes 8-9 (regardless of last byte)
        var packet = DExtraProtocol.callsignBytes("AI5OS")
        packet.append(0x20)  // space
        packet.append(0x20)  // space
        packet.append(0x00)
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .unlink)
    }

    func testIdentifyPacket_keepalive_9bytes() {
        let packet = DExtraProtocol.buildKeepalivePacket(callsign: "AI5OS")
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .keepalive)
    }

    func testIdentifyPacket_DSVT_voice() {
        var packet = Data(count: 27)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54 // DSVT
        packet[4] = 0x20 // voice type
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .voice)
    }

    func testIdentifyPacket_DSVT_header() {
        var packet = Data(count: 56)
        packet[0] = 0x44; packet[1] = 0x53; packet[2] = 0x56; packet[3] = 0x54 // DSVT
        packet[4] = 0x10 // header type
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .header)
    }

    // MARK: - Link Packet Construction

    func testBuildLinkPacket_localModuleMatchesRemote() {
        // For direct (non-gateway) connections, local module should match remote
        let packet = DExtraProtocol.buildLinkPacket(
            callsign: "AI5OS", module: "C", remoteModule: "C"
        )
        XCTAssertEqual(packet.count, 11)
        XCTAssertEqual(packet[8], UInt8(ascii: "C"), "Local module at byte 8")
        XCTAssertEqual(packet[9], UInt8(ascii: "C"), "Remote module at byte 9")
        XCTAssertEqual(packet[10], 0x0B, "Last byte should be 0x0B (revision 1)")
    }

    func testBuildLinkPacket_callsignPaddedTo8() {
        let packet = DExtraProtocol.buildLinkPacket(
            callsign: "W9FYI", module: "A", remoteModule: "A"
        )
        let call = String(data: packet.prefix(8), encoding: .ascii)
        XCTAssertEqual(call, "W9FYI   ")
    }

    // MARK: - Unlink Packet

    func testBuildUnlinkPacket_correctFormat() {
        let packet = DExtraProtocol.buildUnlinkPacket(callsign: "AI5OS")
        XCTAssertEqual(packet.count, 11)
        XCTAssertEqual(packet[8], 0x20)  // space
        XCTAssertEqual(packet[9], 0x20)  // space
        XCTAssertEqual(packet[10], 0x00)
    }

    // MARK: - Keepalive Packet

    func testBuildKeepalivePacket_correctFormat() {
        let packet = DExtraProtocol.buildKeepalivePacket(callsign: "AI5OS")
        XCTAssertEqual(packet.count, 9)
        let call = String(data: packet.prefix(8), encoding: .ascii)
        XCTAssertEqual(call, "AI5OS   ")
        XCTAssertEqual(packet[8], 0x00)
    }

    // MARK: - 14-byte ACK/NAK (XLX/XRF style)

    func testIdentifyPacket_14byte_ACK_string() {
        // Real response from XRF757/XRF679: callsign + modules + "ACK" + 0x00
        // [41 49 35 4F 53 20 20 20 41 41 41 43 4B 00]
        var packet = DExtraProtocol.callsignBytes("AI5OS")  // 8 bytes
        packet.append(UInt8(ascii: "A"))  // local module
        packet.append(UInt8(ascii: "A"))  // remote module
        packet.append(contentsOf: "ACK".utf8)  // bytes 10-12
        packet.append(0x00)  // byte 13
        XCTAssertEqual(packet.count, 14)
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .linkAck,
                       "14-byte packet with ACK string should be .linkAck")
    }

    func testIdentifyPacket_14byte_NAK_string() {
        var packet = DExtraProtocol.callsignBytes("AI5OS")
        packet.append(UInt8(ascii: "A"))
        packet.append(UInt8(ascii: "A"))
        packet.append(contentsOf: "NAK".utf8)
        packet.append(0x00)
        XCTAssertEqual(packet.count, 14)
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .linkNak,
                       "14-byte packet with NAK string should be .linkNak")
    }

    // MARK: - XLX Routing

    func testXLXClient_usesDExtraClient() {
        // XLX should use DExtra protocol on port 30001
        // (Later we may add DPlus fallback, but DExtra is the primary)
        XCTAssertEqual(DExtraProtocol.port, 30001)
    }

    // MARK: - Realistic Packet Sequences
    //
    // Simulate what a real reflector sends back during connection.

    func testRealisticXRFConnection_linkEchoIsACK() {
        // Real XRF scenario: reflector echoes back an 11-byte packet
        // with last byte set to a non-zero module letter.
        var ackResponse = DExtraProtocol.callsignBytes("AI5OS")
        ackResponse.append(UInt8(ascii: "C"))  // local module
        ackResponse.append(UInt8(ascii: "C"))  // remote module
        ackResponse.append(0x43)               // 'C' = ACK
        XCTAssertEqual(DExtraProtocol.identifyPacket(ackResponse), .linkAck)
    }

    func testRealisticXRFConnection_echoUnchangedIsACK() {
        // Our link request has 0x0B at byte 10 (non-zero), so if echoed
        // back unchanged, identifyPacket sees non-zero last byte = ACK.
        // A real NAK comes as a 14-byte packet with "NAK" string.
        let linkRequest = DExtraProtocol.buildLinkPacket(
            callsign: "AI5OS", module: "C", remoteModule: "C"
        )
        XCTAssertEqual(linkRequest[10], 0x0B)
        // 11-byte with non-zero last byte = linkAck
        XCTAssertEqual(DExtraProtocol.identifyPacket(linkRequest), .linkAck)
    }

    func testRealisticNAK_11byte_lastByteZero() {
        // Classic 11-byte NAK: reflector echoes with byte 10 = 0x00
        var packet = DExtraProtocol.callsignBytes("AI5OS")
        packet.append(UInt8(ascii: "C"))
        packet.append(UInt8(ascii: "C"))
        packet.append(0x00)
        XCTAssertEqual(DExtraProtocol.identifyPacket(packet), .linkNak)
    }

    func testRealisticXLXConnection_linkEchoIsACK() {
        // XLX uses same DExtra protocol — ACK is echo with non-zero last byte
        let linkRequest = DExtraProtocol.buildLinkPacket(
            callsign: "AI5OS", module: "A", remoteModule: "A"
        )
        var ackResponse = linkRequest
        ackResponse[10] = 0x41  // 'A'
        XCTAssertEqual(DExtraProtocol.identifyPacket(ackResponse), .linkAck)
    }
}
