// DCSProtocolTests.swift — Tests for DCS protocol constants and packet builders

import XCTest
@testable import TH_Programmer

final class DCSProtocolTests: XCTestCase {
    nonisolated deinit {}

    func testPort_is30051() {
        XCTAssertEqual(DCSProtocol.port, 30051)
    }

    func testKeepaliveInterval_is10Seconds() {
        XCTAssertEqual(DCSProtocol.keepaliveInterval, 10.0)
    }

    func testVoiceFrameLength_is100() {
        XCTAssertEqual(DCSProtocol.voiceFrameLength, 100)
    }

    func testPadCallsign_shorterThan8() {
        XCTAssertEqual(DCSProtocol.padCallsign("AI5OS"), "AI5OS   ")
    }

    func testPadCallsign_exactly8() {
        XCTAssertEqual(DCSProtocol.padCallsign("AI5OS  X"), "AI5OS  X")
    }

    func testPadCallsign_uppercased() {
        XCTAssertEqual(DCSProtocol.padCallsign("ai5os"), "AI5OS   ")
    }

    func testCallsignBytes_length() {
        let bytes = DCSProtocol.callsignBytes("AI5OS")
        XCTAssertEqual(bytes.count, 8)
    }

    func testBuildConnectPacket_length() {
        let packet = DCSProtocol.buildConnectPacket(callsign: "AI5OS", remoteModule: "A")
        XCTAssertEqual(packet.count, 519)
    }

    func testBuildConnectPacket_callsignAtStart() {
        let packet = DCSProtocol.buildConnectPacket(callsign: "AI5OS", remoteModule: "B")
        let cs = String(data: packet[0..<8], encoding: .ascii)
        XCTAssertEqual(cs, "AI5OS   ")
    }

    func testBuildConnectPacket_moduleBytes() {
        let packet = DCSProtocol.buildConnectPacket(callsign: "AI5OS", localModule: "C", remoteModule: "B")
        XCTAssertEqual(packet[8], Character("C").asciiValue!)
        XCTAssertEqual(packet[9], Character("B").asciiValue!)
    }

    func testBuildDisconnectPacket_length() {
        let packet = DCSProtocol.buildDisconnectPacket(callsign: "AI5OS")
        XCTAssertEqual(packet.count, 519)
    }

    func testBuildDisconnectPacket_spacesAtModuleBytes() {
        let packet = DCSProtocol.buildDisconnectPacket(callsign: "AI5OS")
        XCTAssertEqual(packet[8], 0x20)
        XCTAssertEqual(packet[9], 0x20)
    }

    func testBuildPollPacket_length() {
        let packet = DCSProtocol.buildPollPacket(callsign: "AI5OS")
        XCTAssertEqual(packet.count, 17)
    }

    func testBuildPollPacket_callsignAtStart() {
        let packet = DCSProtocol.buildPollPacket(callsign: "AI5OS")
        let cs = String(data: packet[0..<8], encoding: .ascii)
        XCTAssertEqual(cs, "AI5OS   ")
    }

    func testBuildPollPacket_nullSeparatorAtByte8() {
        let packet = DCSProtocol.buildPollPacket(callsign: "AI5OS", reflectorCallsign: "DCS001")
        XCTAssertEqual(packet[8], 0x00)
    }

    func testBuildPollPacket_reflectorCallsignAtByte9() {
        let packet = DCSProtocol.buildPollPacket(callsign: "AI5OS", reflectorCallsign: "DCS001")
        let refCS = String(data: packet[9..<17], encoding: .ascii)
        XCTAssertEqual(refCS, "DCS001  ")
    }

    func testRandomStreamID_nonZero() {
        let id = DCSProtocol.randomStreamID()
        XCTAssertGreaterThan(id, 0)
    }

    func testHostname_DCS() {
        XCTAssertEqual(DCSProtocol.hostname(number: 1), "dcs001.dstargateway.org")
        XCTAssertEqual(DCSProtocol.hostname(number: 999), "dcs999.dstargateway.org")
        XCTAssertEqual(DCSProtocol.hostname(number: 42), "dcs042.dstargateway.org")
    }

    func testIdentifyPacket_empty() {
        XCTAssertEqual(DCSProtocol.identifyPacket(Data()) == .unknown, true)
    }

    func testIdentifyPacket_ack14Bytes() {
        var data = Data(count: 14)
        // "ACK" at offset 10
        data[10] = 0x41; data[11] = 0x43; data[12] = 0x4B
        XCTAssertEqual(DCSProtocol.identifyPacket(data) == .linkAck, true)
    }

    func testIdentifyPacket_nak14Bytes() {
        var data = Data(count: 14)
        // "NAK" at offset 10
        data[10] = 0x4E; data[11] = 0x41; data[12] = 0x4B
        XCTAssertEqual(DCSProtocol.identifyPacket(data) == .linkNak, true)
    }

    func testIdentifyPacket_control519() {
        let data = Data(count: 519)
        XCTAssertEqual(DCSProtocol.identifyPacket(data) == .control, true)
    }

    func testIdentifyPacket_control17() {
        let data = Data(count: 17)
        XCTAssertEqual(DCSProtocol.identifyPacket(data) == .control, true)
    }
}
