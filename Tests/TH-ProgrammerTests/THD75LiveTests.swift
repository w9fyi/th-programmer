// THD75LiveTests.swift — TDD tests for THD75LiveConnection, LiveRadioState, FO/ME/MN parsers

import XCTest
@testable import TH_Programmer

final class THD75LiveTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - LiveRadioState defaults

    func testDefaultState() {
        let s = LiveRadioState()
        XCTAssertEqual(s.frequencyHz, 0)
        XCTAssertEqual(s.mode, 0)
        XCTAssertFalse(s.ptt)
        XCTAssertFalse(s.busy)
        XCTAssertEqual(s.vfo, 0)
        XCTAssertEqual(s.shift, 0)
    }

    // MARK: - FO response parser

    // Sample: 146.520 MHz, FM, simplex, no tone
    private let sampleFO = "FO 0,0146520000,00,0,0,0,0,08,08,000,0,00600000,0"

    func testParseFOResponse_frequency() {
        let state = LiveRadioState(foResponse: sampleFO)
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.frequencyHz, 146_520_000)
    }

    func testParseFOResponse_vfoBand() {
        let raw = "FO 1,0446000000,00,0,0,0,0,08,08,000,0,00600000,0"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertEqual(state?.vfo, 1)
        XCTAssertEqual(state?.frequencyHz, 446_000_000)
    }

    func testParseFOResponse_modeFM() {
        let state = LiveRadioState(foResponse: sampleFO)
        XCTAssertEqual(state?.mode, 0)   // 0 = FM
    }

    func testParseFOResponse_modeDV() {
        let raw = "FO 0,0145670000,00,0,0,0,0,08,08,000,0,00000000,1"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertEqual(state?.mode, 1)   // 1 = DV
    }

    func testParseFOResponse_shiftMinus() {
        // Shift field (index 10): 2 = minus (negative) offset, offset = 600 kHz
        let raw = "FO 0,0146880000,00,0,0,0,0,08,08,000,2,00600000,0"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertEqual(state?.shift, 2)
        XCTAssertEqual(state?.offsetHz, 600_000)
    }

    func testParseFOResponse_shiftPlus() {
        // Shift 1 = plus offset
        let raw = "FO 0,0147120000,00,0,0,0,0,08,08,000,1,00600000,0"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertEqual(state?.shift, 1)
    }

    func testParseFOResponse_ctcssOn() {
        // CTCSS on (field index 5 = 1), index 8 = 100.0 Hz
        let raw = "FO 0,0146880000,00,0,0,1,0,08,08,000,2,00600000,0"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertTrue(state?.ctcssEnabled ?? false)
        XCTAssertEqual(state?.ctcssIndex, 8)
    }

    func testParseFOResponse_toneOn() {
        // Tone on (field index 4 = 1)
        let raw = "FO 0,0146880000,00,0,1,0,0,08,08,000,2,00600000,0"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertTrue(state?.toneEnabled ?? false)
    }

    func testParseFOResponse_simplex() {
        let state = LiveRadioState(foResponse: sampleFO)
        XCTAssertEqual(state?.shift, 0)    // simplex
    }

    func testParseFOResponse_invalidPrefix() {
        XCTAssertNil(LiveRadioState(foResponse: "XX 0,0146520000,00,0,0,0,0,08,08,000,0,00600000,0"))
    }

    func testParseFOResponse_emptyString() {
        XCTAssertNil(LiveRadioState(foResponse: ""))
    }

    func testParseFOResponse_tooFewFields() {
        XCTAssertNil(LiveRadioState(foResponse: "FO 0,0146520000"))
    }

    func testParseFOResponse_trailingCR() {
        // Radio responses include \r — parser must strip it
        let raw = "FO 0,0146520000,00,0,0,0,0,08,08,000,0,00600000,0\r"
        let state = LiveRadioState(foResponse: raw)
        XCTAssertNotNil(state)
        XCTAssertEqual(state?.frequencyHz, 146_520_000)
    }

    // MARK: - FO command builder

    func testBuildFOCommand_prefix() {
        var s = LiveRadioState()
        s.vfo = 0
        s.frequencyHz = 146_520_000
        s.mode = 0
        XCTAssertTrue(s.foCommand.hasPrefix("FO 0,0146520000,"))
    }

    func testBuildFOCommand_vfoB() {
        var s = LiveRadioState()
        s.vfo = 1
        s.frequencyHz = 446_000_000
        XCTAssertTrue(s.foCommand.hasPrefix("FO 1,0446000000,"))
    }

    func testBuildFOCommand_modeSuffix() {
        var s = LiveRadioState()
        s.vfo = 0
        s.frequencyHz = 146_520_000
        s.mode = 0  // FM
        XCTAssertTrue(s.foCommand.hasSuffix(",0"))
    }

    func testBuildFOCommand_modeDV() {
        var s = LiveRadioState()
        s.frequencyHz = 145_670_000
        s.mode = 1  // DV
        XCTAssertTrue(s.foCommand.hasSuffix(",1"))
    }

    func testFOCommandRoundTrip_frequency() {
        var s = LiveRadioState()
        s.vfo = 0
        s.frequencyHz = 446_000_000
        s.mode = 0
        let parsed = LiveRadioState(foResponse: s.foCommand)
        XCTAssertNotNil(parsed)
        XCTAssertEqual(parsed?.frequencyHz, 446_000_000)
    }

    func testFOCommandRoundTrip_shiftAndOffset() {
        var s = LiveRadioState()
        s.vfo = 0
        s.frequencyHz = 146_880_000
        s.shift = 2            // minus
        s.offsetHz = 600_000
        s.ctcssEnabled = true
        s.ctcssIndex = 3
        s.mode = 0
        let parsed = LiveRadioState(foResponse: s.foCommand)
        XCTAssertEqual(parsed?.shift, 2)
        XCTAssertEqual(parsed?.offsetHz, 600_000)
        XCTAssertTrue(parsed?.ctcssEnabled ?? false)
        XCTAssertEqual(parsed?.ctcssIndex, 3)
    }

    // MARK: - frequencyMHz formatted string

    func testFrequencyMHz_VHF() {
        var s = LiveRadioState()
        s.frequencyHz = 146_520_000
        XCTAssertEqual(s.frequencyMHz, "146.5200")
    }

    func testFrequencyMHz_UHF() {
        var s = LiveRadioState()
        s.frequencyHz = 446_000_000
        XCTAssertEqual(s.frequencyMHz, "446.0000")
    }

    func testFrequencyMHz_220() {
        var s = LiveRadioState()
        s.frequencyHz = 223_500_000
        XCTAssertEqual(s.frequencyMHz, "223.5000")
    }

    // MARK: - modeName

    func testModeNameFM()  { var s = LiveRadioState(); s.mode = 0; XCTAssertEqual(s.modeName, "FM") }
    func testModeNameDV()  { var s = LiveRadioState(); s.mode = 1; XCTAssertEqual(s.modeName, "DV") }
    func testModeNameAM()  { var s = LiveRadioState(); s.mode = 2; XCTAssertEqual(s.modeName, "AM") }
    func testModeNameNFM() { var s = LiveRadioState(); s.mode = 6; XCTAssertEqual(s.modeName, "NFM") }
    func testModeNameDR()  { var s = LiveRadioState(); s.mode = 7; XCTAssertEqual(s.modeName, "DR") }
    func testModeNameUnknown() { var s = LiveRadioState(); s.mode = 99; XCTAssertEqual(s.modeName, "??") }

    // MARK: - Equatable

    func testEquatable_sameState() {
        let s1 = LiveRadioState()
        let s2 = LiveRadioState()
        XCTAssertEqual(s1, s2)
    }

    func testEquatable_differentFreq() {
        var s1 = LiveRadioState(); s1.frequencyHz = 146_520_000
        var s2 = LiveRadioState(); s2.frequencyHz = 446_000_000
        XCTAssertNotEqual(s1, s2)
    }

    func testEquatable_differentMode() {
        var s1 = LiveRadioState(); s1.mode = 0
        var s2 = LiveRadioState(); s2.mode = 1
        XCTAssertNotEqual(s1, s2)
    }

    // MARK: - ME command builder

    private func simplexFM(_ number: Int, freq: UInt32) -> ChannelMemory {
        var ch = ChannelMemory(number: number)
        ch.empty = false
        ch.freq = freq
        ch.offset = 600_000
        ch.duplex = .simplex
        ch.mode = .fm
        ch.toneMode = .none
        ch.rtone = 88.5
        ch.ctone = 88.5
        ch.dtcs = 23
        ch.tuningStep = 5.0
        ch.skip = false
        ch.name = "TEST    "
        return ch
    }

    func testMECommand_prefix() {
        let ch = simplexFM(1, freq: 146_520_000)
        XCTAssertTrue(ch.meCommand.hasPrefix("ME 0001,"))
    }

    func testMECommand_channelNumberPadding() {
        let ch = simplexFM(42, freq: 146_520_000)
        XCTAssertTrue(ch.meCommand.hasPrefix("ME 0042,"))
    }

    func testMECommand_frequency() {
        let ch = simplexFM(1, freq: 146_520_000)
        // Field 1 (after channel): 10-digit zero-padded Hz
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[1]), "0146520000")
    }

    func testMECommand_simplexShift() {
        let ch = simplexFM(1, freq: 146_520_000)
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[3]), "0")   // shift = 0 (simplex)
    }

    func testMECommand_plusShift() {
        var ch = simplexFM(1, freq: 147_120_000)
        ch.duplex = .plus
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[3]), "1")
    }

    func testMECommand_minusShift() {
        var ch = simplexFM(1, freq: 146_880_000)
        ch.duplex = .minus
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[3]), "2")
    }

    func testMECommand_noTone() {
        let ch = simplexFM(1, freq: 146_520_000)
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[4]), "0")   // tone TX off
        XCTAssertEqual(String(fields[5]), "0")   // CTCSS off
        XCTAssertEqual(String(fields[6]), "0")   // DCS off
    }

    func testMECommand_toneEnabled() {
        var ch = simplexFM(1, freq: 146_520_000)
        ch.toneMode = .tone
        ch.rtone = 100.0
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[4]), "1")   // tone TX on
        XCTAssertEqual(String(fields[5]), "0")
        XCTAssertEqual(String(fields[6]), "0")
        // 100.0 Hz is index 12 in CTCSS_TONES
        XCTAssertEqual(String(fields[7]), "12")
    }

    func testMECommand_ctcssEnabled() {
        var ch = simplexFM(1, freq: 146_880_000)
        ch.duplex = .minus
        ch.toneMode = .tsql
        ch.ctone = 127.3   // index 19
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[4]), "0")
        XCTAssertEqual(String(fields[5]), "1")   // CTCSS on
        XCTAssertEqual(String(fields[8]), "19")
    }

    func testMECommand_dcsEnabled() {
        var ch = simplexFM(1, freq: 146_520_000)
        ch.toneMode = .dtcs
        ch.dtcs = 23       // first DTCS code, index 0
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[6]), "1")   // DCS on
        XCTAssertEqual(String(fields[9]), "000") // index 0, 3-digit
    }

    func testMECommand_mode_FM() {
        let ch = simplexFM(1, freq: 146_520_000)
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[11]), "0")  // FM = 0
    }

    func testMECommand_mode_NFM() {
        var ch = simplexFM(1, freq: 446_000_000)
        ch.mode = .nfm
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[11]), "6")  // NFM = 6
    }

    func testMECommand_skip() {
        var ch = simplexFM(1, freq: 146_520_000)
        ch.skip = true
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[12]), "1")
    }

    func testMECommand_offset() {
        var ch = simplexFM(1, freq: 146_880_000)
        ch.duplex = .minus
        ch.offset = 600_000
        let fields = ch.meCommand.dropFirst(3).split(separator: ",", omittingEmptySubsequences: false)
        XCTAssertEqual(String(fields[10]), "00600000")
    }

    // MARK: - MN command builder

    func testMNCommand_format() {
        var ch = simplexFM(1, freq: 146_520_000)
        ch.name = "W5YI    "
        XCTAssertEqual(ch.mnCommand, "MN 0001,W5YI    ")
    }

    func testMNCommand_shortNamePadded() {
        var ch = simplexFM(5, freq: 146_520_000)
        ch.name = "AB"
        // Should be padded to 8 chars
        XCTAssertEqual(ch.mnCommand, "MN 0005,AB      ")
    }

    func testMNCommand_longNameTruncated() {
        var ch = simplexFM(10, freq: 146_520_000)
        ch.name = "TOOLONGNAME"
        let cmd = ch.mnCommand
        // After "MN 0010," should be exactly 8 chars
        let namePart = String(cmd.dropFirst("MN 0010,".count))
        XCTAssertEqual(namePart.count, 8)
    }

    // MARK: - AG response parser

    func testParseAGResponse_normal() {
        XCTAssertEqual(THD75LiveConnection.parseAGResponse("AG 069"), 69)
    }

    func testParseAGResponse_zero() {
        XCTAssertEqual(THD75LiveConnection.parseAGResponse("AG 000"), 0)
    }

    func testParseAGResponse_max() {
        XCTAssertEqual(THD75LiveConnection.parseAGResponse("AG 100"), 100)
    }

    func testParseAGResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseAGResponse("AG 069\r"), 69)
    }

    func testParseAGResponse_invalidPrefix() {
        XCTAssertNil(THD75LiveConnection.parseAGResponse("XX 069"))
    }

    // MARK: - BL response parser

    func testParseBLResponse_level4() {
        XCTAssertEqual(THD75LiveConnection.parseBLResponse("BL 4"), 4)
    }

    func testParseBLResponse_zero() {
        XCTAssertEqual(THD75LiveConnection.parseBLResponse("BL 0"), 0)
    }

    func testParseBLResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseBLResponse("XX 4"))
    }

    // MARK: - BS response parser

    func testParseBSResponse_on() {
        XCTAssertEqual(THD75LiveConnection.parseBSResponse("BS 1"), true)
    }

    func testParseBSResponse_off() {
        XCTAssertEqual(THD75LiveConnection.parseBSResponse("BS 0"), false)
    }

    func testParseBSResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseBSResponse("XX 1"))
    }

    // MARK: - PS response parser

    func testParsePSResponse_on() {
        XCTAssertEqual(THD75LiveConnection.parsePSResponse("PS 1"), 1)
    }

    func testParsePSResponse_off() {
        XCTAssertEqual(THD75LiveConnection.parsePSResponse("PS 0"), 0)
    }

    func testParsePSResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parsePSResponse("XX 1"))
    }

    // MARK: - VX response parser

    func testParseVXResponse_off() {
        XCTAssertEqual(THD75LiveConnection.parseVXResponse("VX 0"), false)
    }

    func testParseVXResponse_on() {
        XCTAssertEqual(THD75LiveConnection.parseVXResponse("VX 1"), true)
    }

    func testParseVXResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseVXResponse("XX 0"))
    }

    // MARK: - CS response parser

    func testParseCSResponse_normal() {
        XCTAssertEqual(THD75LiveConnection.parseCSResponse("CS AI5OS"), "AI5OS")
    }

    func testParseCSResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseCSResponse("CS AI5OS\r"), "AI5OS")
    }

    func testParseCSResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseCSResponse("XX AI5OS"))
    }

    // MARK: - DL response parser

    func testParseDLResponse_unlocked() {
        XCTAssertEqual(THD75LiveConnection.parseDLResponse("DL 0"), false)
    }

    func testParseDLResponse_locked() {
        XCTAssertEqual(THD75LiveConnection.parseDLResponse("DL 1"), true)
    }

    func testParseDLResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseDLResponse("XX 0"))
    }

    // MARK: - FV response parser

    func testParseFVResponse_normal() {
        XCTAssertEqual(THD75LiveConnection.parseFVResponse("FV 1.03"), "1.03")
    }

    func testParseFVResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseFVResponse("FV 1.03\r"), "1.03")
    }

    func testParseFVResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseFVResponse("XX 1.03"))
    }

    // MARK: - AE response parser

    func testParseAEResponse_serial() {
        let result = THD75LiveConnection.parseAEResponse("AE C5310165,K01")
        XCTAssertEqual(result?.serial, "C5310165")
    }

    func testParseAEResponse_model() {
        let result = THD75LiveConnection.parseAEResponse("AE C5310165,K01")
        XCTAssertEqual(result?.model, "K01")
    }

    func testParseAEResponse_trailingCR() {
        let result = THD75LiveConnection.parseAEResponse("AE C5310165,K01\r")
        XCTAssertNotNil(result)
        XCTAssertEqual(result?.serial, "C5310165")
    }

    func testParseAEResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseAEResponse("XX C5310165,K01"))
    }

    // MARK: - RT response parser

    func testParseRTResponse_normal() {
        XCTAssertEqual(THD75LiveConnection.parseRTResponse("RT 260323080922"), "260323080922")
    }

    func testParseRTResponse_trailingCR() {
        XCTAssertEqual(THD75LiveConnection.parseRTResponse("RT 260323080922\r"), "260323080922")
    }

    func testParseRTResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseRTResponse("XX 260323080922"))
    }

    // MARK: - GP response parser

    func testParseGPResponse_enabled() {
        let result = THD75LiveConnection.parseGPResponse("GP 1,0")
        XCTAssertEqual(result?.enabled, true)
        XCTAssertEqual(result?.mode, 0)
    }

    func testParseGPResponse_disabled() {
        let result = THD75LiveConnection.parseGPResponse("GP 0,0")
        XCTAssertEqual(result?.enabled, false)
    }

    func testParseGPResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseGPResponse("XX 1,0"))
    }

    // MARK: - GS response parser

    func testParseGSResponse_fixed() {
        XCTAssertEqual(THD75LiveConnection.parseGSResponse("GS 1,0,0,0,0,0"), true)
    }

    func testParseGSResponse_notFixed() {
        XCTAssertEqual(THD75LiveConnection.parseGSResponse("GS 0,0,0,0,0,0"), false)
    }

    func testParseGSResponse_invalid() {
        XCTAssertNil(THD75LiveConnection.parseGSResponse("XX 1,0,0,0,0,0"))
    }

    // MARK: - RT clock formatting helper

    func testRTClockString_formatsDate() {
        // "260323080922" → "2026-03-23 08:09"
        XCTAssertEqual(THD75LiveConnection.formatClockString("260323080922"), "2026-03-23 08:09")
    }

    func testRTClockString_invalidLength() {
        XCTAssertNil(THD75LiveConnection.formatClockString("2603"))
    }

    // MARK: - NMEA position parser

    // Typical $GPRMC from TH-D75 GPS — Austin, TX area
    private let sampleRMC = "$GPRMC,080922,A,3242.9432,N,09704.3782,W,0.0,127.3,260323,,*1A"

    func testParseNMEA_latitude() {
        let pos = THD75LiveConnection.parseNMEAPosition(sampleRMC)
        XCTAssertNotNil(pos)
        // 32° 42.9432' N = 32 + 42.9432/60 ≈ 32.7157°
        XCTAssertEqual(pos!.latitude,  32.7157, accuracy: 0.0001)
    }

    func testParseNMEA_longitude() {
        let pos = THD75LiveConnection.parseNMEAPosition(sampleRMC)
        // 097° 04.3782' W = -(97 + 4.3782/60) ≈ -97.0730°
        XCTAssertEqual(pos!.longitude, -97.0730, accuracy: 0.0001)
    }

    func testParseNMEA_speed() {
        let pos = THD75LiveConnection.parseNMEAPosition(sampleRMC)
        XCTAssertEqual(pos!.speedKnots, 0.0, accuracy: 0.01)
    }

    func testParseNMEA_track() {
        let pos = THD75LiveConnection.parseNMEAPosition(sampleRMC)
        XCTAssertEqual(pos!.trackDegrees, 127.3, accuracy: 0.01)
    }

    func testParseNMEA_voidStatus() {
        let raw = "$GPRMC,080922,V,3242.9432,N,09704.3782,W,0.0,0.0,260323,,*1A"
        XCTAssertNil(THD75LiveConnection.parseNMEAPosition(raw))
    }

    func testParseNMEA_wrongSentenceType() {
        let raw = "$GPGGA,080922,3242.9432,N,09704.3782,W,1,08,0.9,305.4,M,-22.5,M,,*47"
        XCTAssertNil(THD75LiveConnection.parseNMEAPosition(raw))
    }

    func testParseNMEA_southernHemisphere() {
        let raw = "$GPRMC,120000,A,3347.5600,S,07040.1200,W,0.0,0.0,260323,,*1A"
        let pos = THD75LiveConnection.parseNMEAPosition(raw)
        XCTAssertNotNil(pos)
        XCTAssertLessThan(pos!.latitude, 0)
        XCTAssertLessThan(pos!.longitude, 0)
    }

    func testParseNMEA_easternHemisphere() {
        let raw = "$GPRMC,120000,A,3547.5600,N,13940.1200,E,0.0,0.0,260323,,*1A"
        let pos = THD75LiveConnection.parseNMEAPosition(raw)
        XCTAssertNotNil(pos)
        XCTAssertGreaterThan(pos!.latitude,  0)
        XCTAssertGreaterThan(pos!.longitude, 0)
    }

    func testParseNMEA_missingChecksum() {
        let raw = "$GPRMC,080922,A,3242.9432,N,09704.3782,W,1.5,90.0,260323,,"
        let pos = THD75LiveConnection.parseNMEAPosition(raw)
        XCTAssertNotNil(pos)
        XCTAssertEqual(pos!.speedKnots, 1.5, accuracy: 0.01)
    }

    func testParseNMEA_emptyString() {
        XCTAssertNil(THD75LiveConnection.parseNMEAPosition(""))
    }

    func testParseNMEA_coordinateString() {
        let pos = NMEAPosition(latitude: 32.7157, longitude: -97.0730,
                               speedKnots: 0, trackDegrees: 0)
        XCTAssertEqual(pos.coordinateString, "32.7157° N, 97.0730° W")
    }

    func testParseNMEA_speedString_stationary() {
        let pos = NMEAPosition(latitude: 32.7157, longitude: -97.0730,
                               speedKnots: 0.05, trackDegrees: 0)
        XCTAssertNil(pos.speedString)
    }

    func testParseNMEA_speedString_moving() {
        let pos = NMEAPosition(latitude: 32.7157, longitude: -97.0730,
                               speedKnots: 3.4, trackDegrees: 0)
        XCTAssertEqual(pos.speedString, "3.4 kn")
    }
}
