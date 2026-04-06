// URCALLCommandTests.swift — Tests for URCALL command parsing

import XCTest
@testable import TH_Programmer

final class URCALLCommandTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Link Commands

    func testParseREFLink() {
        let cmd = URCALLCommand.parse("REF001CL")
        let expected = ReflectorTarget(type: .ref, number: 1, module: "C")
        XCTAssertEqual(cmd, .link(expected))
    }

    func testParseXRFLink() {
        let cmd = URCALLCommand.parse("XRF757AL")
        let expected = ReflectorTarget(type: .xrf, number: 757, module: "A")
        XCTAssertEqual(cmd, .link(expected))
    }

    func testParseDCSLink() {
        let cmd = URCALLCommand.parse("DCS006BL")
        let expected = ReflectorTarget(type: .dcs, number: 6, module: "B")
        XCTAssertEqual(cmd, .link(expected))
    }

    func testParseXLXLink() {
        let cmd = URCALLCommand.parse("XLX999ZL")
        let expected = ReflectorTarget(type: .xlx, number: 999, module: "Z")
        XCTAssertEqual(cmd, .link(expected))
    }

    func testParseLinkModuleD() {
        let cmd = URCALLCommand.parse("REF030DL")
        let expected = ReflectorTarget(type: .ref, number: 30, module: "D")
        XCTAssertEqual(cmd, .link(expected))
    }

    // MARK: - Unlink Commands

    func testParseSpecificUnlink() {
        // REF001CU — unlink from specific reflector
        let cmd = URCALLCommand.parse("REF001CU")
        XCTAssertEqual(cmd, .unlink)
    }

    func testParseGenericUnlink() {
        // 7 spaces + U
        let cmd = URCALLCommand.parse("       U")
        XCTAssertEqual(cmd, .unlink)
    }

    func testParseDCSUnlink() {
        let cmd = URCALLCommand.parse("DCS006BU")
        XCTAssertEqual(cmd, .unlink)
    }

    // MARK: - Info Command

    func testParseInfoCommand() {
        let cmd = URCALLCommand.parse("       I")
        XCTAssertEqual(cmd, .info)
    }

    // MARK: - Echo Command

    func testParseEchoCommand() {
        let cmd = URCALLCommand.parse("       E")
        XCTAssertEqual(cmd, .echo)
    }

    // MARK: - Voice (Normal Traffic)

    func testParseCQCQCQ() {
        let cmd = URCALLCommand.parse("CQCQCQ  ")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseCQCQCQNoSpaces() {
        let cmd = URCALLCommand.parse("CQCQCQ")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseEmptyString() {
        let cmd = URCALLCommand.parse("")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseAllSpaces() {
        let cmd = URCALLCommand.parse("        ")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseShortString() {
        let cmd = URCALLCommand.parse("AB")
        XCTAssertEqual(cmd, .voice)
    }

    // MARK: - Edge Cases

    func testParseInvalidPrefix() {
        // ABC is not a valid reflector type
        let cmd = URCALLCommand.parse("ABC001AL")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseInvalidNumber_zero() {
        // 000 is not valid (must be 1-999)
        let cmd = URCALLCommand.parse("REF000AL")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseInvalidNumber_letters() {
        let cmd = URCALLCommand.parse("REFABCAL")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseInvalidModule_digit() {
        // Module must be a letter
        let cmd = URCALLCommand.parse("REF0011L")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseNoCommandSuffix() {
        // REF001C without L or U — not a command
        let cmd = URCALLCommand.parse("REF001C ")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseLowercasePrefix() {
        // Lowercase "ref" should still match (radio sends uppercase, but be robust)
        let cmd = URCALLCommand.parse("ref001CL")
        let expected = ReflectorTarget(type: .ref, number: 1, module: "C")
        XCTAssertEqual(cmd, .link(expected))
    }

    func testParseLowercaseModule() {
        // Lowercase module letter should be uppercased
        let cmd = URCALLCommand.parse("REF001cL")
        let expected = ReflectorTarget(type: .ref, number: 1, module: "C")
        XCTAssertEqual(cmd, .link(expected))
    }

    func testParseSingleCharNotCommand() {
        // 7 spaces + X (not U/I/E) — not a recognized command
        let cmd = URCALLCommand.parse("       X")
        XCTAssertEqual(cmd, .voice)
    }

    func testParseCallsignNotCommand() {
        // A regular callsign in YOUR field
        let cmd = URCALLCommand.parse("W1AW   ")
        XCTAssertEqual(cmd, .voice)
    }

    // MARK: - ReflectorTarget.urCallString Round-Trip

    func testURCallStringRoundTrip() {
        let target = ReflectorTarget(type: .ref, number: 1, module: "C")
        let urcall = target.urCallString  // "REF001CL"
        let cmd = URCALLCommand.parse(urcall)
        XCTAssertEqual(cmd, .link(target))
    }

    func testURCallStringRoundTripDCS() {
        let target = ReflectorTarget(type: .dcs, number: 6, module: "B")
        let urcall = target.urCallString  // "DCS006BL"
        let cmd = URCALLCommand.parse(urcall)
        XCTAssertEqual(cmd, .link(target))
    }

    func testUnlinkCallParsesAsUnlink() {
        let cmd = URCALLCommand.parse(ReflectorTarget.unlinkCall)
        XCTAssertEqual(cmd, .unlink)
    }

    func testInfoCallParsesAsInfo() {
        let cmd = URCALLCommand.parse(ReflectorTarget.infoCall)
        XCTAssertEqual(cmd, .info)
    }
}
