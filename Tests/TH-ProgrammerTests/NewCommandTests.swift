// NewCommandTests.swift — Tests for new CAT parsers and ReflectorTarget model

import XCTest
@testable import TH_Programmer

final class NewCommandTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - PC response parser

    func testParsePCResponse_bandAPowerHigh() {
        let result = THD75LiveConnection.parsePCResponse("PC 0,0")
        XCTAssertEqual(result?.band, 0)
        XCTAssertEqual(result?.power, 0)
    }

    func testParsePCResponse_bandBPowerLow() {
        let result = THD75LiveConnection.parsePCResponse("PC 1,2")
        XCTAssertEqual(result?.band, 1)
        XCTAssertEqual(result?.power, 2)
    }

    func testParsePCResponse_bandAPowerEL() {
        let result = THD75LiveConnection.parsePCResponse("PC 0,3")
        XCTAssertEqual(result?.power, 3)
    }

    func testParsePCResponse_trailingCR() {
        let result = THD75LiveConnection.parsePCResponse("PC 0,3\r")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.power, 3)
    }

    func testParsePCResponse_invalidPrefix() {
        XCTAssertNil(THD75LiveConnection.parsePCResponse("XX 0,0"))
    }

    func testParsePCResponse_missingComma() {
        XCTAssertNil(THD75LiveConnection.parsePCResponse("PC 0"))
    }

    // MARK: - DC response parser

    func testParseDCResponse_validSlot() {
        let result = THD75LiveConnection.parseDCResponse("DC 1,AI5OS,")
        XCTAssertEqual(result?.slot, 1)
        XCTAssertEqual(result?.callsign, "AI5OS")
    }

    func testParseDCResponse_slot6() {
        let result = THD75LiveConnection.parseDCResponse("DC 6,W5YI,")
        XCTAssertEqual(result?.slot, 6)
        XCTAssertEqual(result?.callsign, "W5YI")
    }

    func testParseDCResponse_trailingCR() {
        let result = THD75LiveConnection.parseDCResponse("DC 3,W5YI,\r")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.slot, 3)
        XCTAssertEqual(result?.callsign, "W5YI")
    }

    func testParseDCResponse_invalidPrefix() {
        XCTAssertNil(THD75LiveConnection.parseDCResponse("XX 1,AI5OS,"))
    }

    func testParseDCResponse_emptyCallsign() {
        let result = THD75LiveConnection.parseDCResponse("DC 6,,")
        XCTAssertEqual(result?.slot, 6)
        XCTAssertEqual(result?.callsign, "")
    }

    // MARK: - DS response parser

    func testParseDSResponse_slot1() {
        XCTAssertEqual(THD75LiveConnection.parseDSResponse("DS 1"), 1)
    }

    func testParseDSResponse_slot6() {
        XCTAssertEqual(THD75LiveConnection.parseDSResponse("DS 6"), 6)
    }

    func testParseDSResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseDSResponse("DS 3\r"), 3)
    }

    func testParseDSResponse_invalidPrefix() {
        XCTAssertNil(THD75LiveConnection.parseDSResponse("XX 1"))
    }

    // MARK: - BE response parser

    func testParseBEResponse_success() {
        XCTAssertEqual(THD75LiveConnection.parseBEResponse("BE"), true)
    }

    func testParseBEResponse_failure() {
        XCTAssertEqual(THD75LiveConnection.parseBEResponse("N"), false)
    }

    func testParseBEResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseBEResponse("BE\r"), true)
    }

    func testParseBEResponse_unknown() {
        XCTAssertNil(THD75LiveConnection.parseBEResponse("XX"))
    }

    // MARK: - BT response parser

    func testParseBTResponse_on() {
        XCTAssertEqual(THD75LiveConnection.parseBTResponse("BT 1"), true)
    }

    func testParseBTResponse_off() {
        XCTAssertEqual(THD75LiveConnection.parseBTResponse("BT 0"), false)
    }

    func testParseBTResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseBTResponse("BT 1\r"), true)
    }

    func testParseBTResponse_invalidPrefix() {
        XCTAssertNil(THD75LiveConnection.parseBTResponse("XX 1"))
    }

    // MARK: - AS response parser

    func testParseASResponse_1200() {
        XCTAssertEqual(THD75LiveConnection.parseASResponse("AS 0"), 0)
    }

    func testParseASResponse_9600() {
        XCTAssertEqual(THD75LiveConnection.parseASResponse("AS 1"), 1)
    }

    func testParseASResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseASResponse("AS 0\r"), 0)
    }

    func testParseASResponse_invalidPrefix() {
        XCTAssertNil(THD75LiveConnection.parseASResponse("XX 0"))
    }

    // MARK: - ReflectorTarget model

    func testReflectorTarget_urCallString_REF() {
        let t = ReflectorTarget(type: .ref, number: 1, module: "C")
        XCTAssertEqual(t.urCallString, "REF001CL")
    }

    func testReflectorTarget_urCallString_XRF() {
        let t = ReflectorTarget(type: .xrf, number: 12, module: "A")
        XCTAssertEqual(t.urCallString, "XRF012AL")
    }

    func testReflectorTarget_urCallString_DCS() {
        let t = ReflectorTarget(type: .dcs, number: 999, module: "Z")
        XCTAssertEqual(t.urCallString, "DCS999ZL")
    }

    func testReflectorTarget_urCallString_XLX() {
        let t = ReflectorTarget(type: .xlx, number: 456, module: "B")
        XCTAssertEqual(t.urCallString, "XLX456BL")
    }

    func testReflectorTarget_urCallStringLength() {
        let t = ReflectorTarget(type: .ref, number: 1, module: "A")
        XCTAssertEqual(t.urCallString.count, 8)
    }

    func testReflectorTarget_unlinkCall() {
        XCTAssertEqual(ReflectorTarget.unlinkCall.count, 8)
        XCTAssertTrue(ReflectorTarget.unlinkCall.hasSuffix("U"))
    }

    func testReflectorTarget_infoCall() {
        XCTAssertEqual(ReflectorTarget.infoCall.count, 8)
        XCTAssertTrue(ReflectorTarget.infoCall.hasSuffix("I"))
    }

    func testReflectorTarget_isValid_valid() {
        let t = ReflectorTarget(type: .ref, number: 1, module: "A")
        XCTAssertTrue(t.isValid)
    }

    func testReflectorTarget_isValid_maxNumber() {
        let t = ReflectorTarget(type: .dcs, number: 999, module: "Z")
        XCTAssertTrue(t.isValid)
    }

    func testReflectorTarget_isValid_zeroNumber() {
        let t = ReflectorTarget(type: .ref, number: 0, module: "A")
        XCTAssertFalse(t.isValid)
    }

    func testReflectorTarget_isValid_tooLargeNumber() {
        let t = ReflectorTarget(type: .ref, number: 1000, module: "A")
        XCTAssertFalse(t.isValid)
    }

    func testReflectorTarget_isValid_lowercaseModule() {
        let t = ReflectorTarget(type: .ref, number: 1, module: "a")
        XCTAssertFalse(t.isValid)
    }

    func testReflectorTarget_urCallString_clampsNumber() {
        let t = ReflectorTarget(type: .ref, number: 1500, module: "A")
        XCTAssertEqual(t.urCallString, "REF999AL")
    }

    func testReflectorTarget_equatable() {
        let a = ReflectorTarget(type: .ref, number: 1, module: "A")
        let b = ReflectorTarget(type: .ref, number: 1, module: "A")
        let c = ReflectorTarget(type: .xrf, number: 1, module: "A")
        XCTAssertEqual(a, b)
        XCTAssertNotEqual(a, c)
    }

    func testReflectorType_allCases() {
        XCTAssertEqual(ReflectorTarget.ReflectorType.allCases.count, 4)
    }
}
