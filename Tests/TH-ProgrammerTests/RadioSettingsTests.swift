// RadioSettingsTests.swift — Unit tests for RadioSettings, APRSSettings, DSTARSettings

import XCTest
@testable import TH_Programmer

final class RadioSettingsTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Crash regression: init(from: empty Data) must not trap

    func testInitFromEmptyDataDoesNotCrash() {
        // Regression: on macOS 26, data.index(base, offsetBy:) trapped before the guard ran.
        // This must complete without EXC_BREAKPOINT.
        // All reads from empty Data return 0 (guard idx < endIndex → return 0).
        let settings = RadioSettings(from: Data())
        XCTAssertFalse(settings.beatShift)
        XCTAssertEqual(settings.audioBalance, 0)   // 0 from empty blob
        XCTAssertEqual(settings.cwPitch, 0)         // 0 from empty blob
    }

    func testAPRSInitFromEmptyDataDoesNotCrash() {
        let settings = APRSSettings(from: Data())
        // init(from:) reads raw bytes; empty Data returns 0 for everything
        XCTAssertEqual(settings.symbolCode, 0)
        XCTAssertEqual(settings.beaconInterval, 0)
        XCTAssertEqual(settings.myCallsign, "")
        XCTAssertEqual(settings.mySSID, 0)
    }

    // MARK: - APRS round-trip tests

    func testAPRSCallsignAndSSIDRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.myCallsign = "AI5OS"
        s.mySSID = 9
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.myCallsign, "AI5OS")
        XCTAssertEqual(s2.mySSID, 9)
    }

    func testAPRSCallsignNoSSIDRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.myCallsign = "W5KA"
        s.mySSID = 0
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.myCallsign, "W5KA")
        XCTAssertEqual(s2.mySSID, 0)
    }

    func testAPRSSymbolRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.symbolTable = 0          // primary '/'
        s.symbolCode  = UInt8(ascii: ">")  // car symbol
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.symbolTable, 0)
        XCTAssertEqual(s2.symbolCode, UInt8(ascii: ">"))
    }

    func testAPRSSymbolSecondaryTableRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.symbolTable = 1          // secondary '\'
        s.symbolCode  = UInt8(ascii: "K")
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.symbolTable, 1)
        XCTAssertEqual(s2.symbolCode, UInt8(ascii: "K"))
    }

    func testAPRSBeaconModeAndIntervalRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.beaconMode     = 2   // Auto
        s.beaconInterval = 9   // 60 min
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.beaconMode, 2)
        XCTAssertEqual(s2.beaconInterval, 9)
    }

    func testAPRSSmartBeaconingRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.smartBeaconingLow       = 8
        s.smartBeaconingHigh      = 70
        s.smartBeaconingSlowRate  = 30
        s.smartBeaconingFastRate  = 120
        s.smartBeaconingTurnAngle = 28
        s.smartBeaconingTurnSlope = 26
        s.smartBeaconingTurnTime  = 60
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.smartBeaconingLow,       8)
        XCTAssertEqual(s2.smartBeaconingHigh,      70)
        XCTAssertEqual(s2.smartBeaconingSlowRate,  30)
        XCTAssertEqual(s2.smartBeaconingFastRate,  120)
        XCTAssertEqual(s2.smartBeaconingTurnAngle, 28)
        XCTAssertEqual(s2.smartBeaconingTurnSlope, 26)
        XCTAssertEqual(s2.smartBeaconingTurnTime,  60)
    }

    func testAPRSStatusTextRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.statusText1 = "HELLO !!"
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.statusText1, "HELLO !!")
    }

    func testAPRSStatusText2RoundTrip() {
        // Verifies statusText2 is at a distinct offset from statusText1
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.statusText1 = "TEXT ONE"
        s.statusText2 = "TEXT TWO"
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.statusText1, "TEXT ONE")
        XCTAssertEqual(s2.statusText2, "TEXT TWO")
    }

    func testAPRSStatusText5RoundTrip() {
        // statusText5 is separated from statusText4 by a 16-byte gap (Unknown13F0)
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.statusText4 = "FOURTH"
        s.statusText5 = "FIFTH"
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.statusText4, "FOURTH")
        XCTAssertEqual(s2.statusText5, "FIFTH")
    }

    func testAPRSStatusTxRateRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.statusText1  = "CQ CQ DE AI5OS"
        s.statusTxRate1 = 2  // 1/2
        s.statusTxRate2 = 0  // Off
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.statusTxRate1, 2)
        XCTAssertEqual(s2.statusTxRate2, 0)
    }

    func testAPRSPathTypeRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.pathType    = 1    // Relay
        s.pathWide1_1 = true
        s.pathTotalHops = 3
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.pathType,    1)
        XCTAssertTrue(s2.pathWide1_1)
        XCTAssertEqual(s2.pathTotalHops, 3)
    }

    func testAPRSDataFieldsRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.dataBand  = 1  // B Band
        s.dataSpeed = 1  // 9600 bps
        s.dcdSense  = 2  // Off
        s.txDelay   = 3  // 300 ms
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertEqual(s2.dataBand,  1)
        XCTAssertEqual(s2.dataSpeed, 1)
        XCTAssertEqual(s2.dcdSense,  2)
        XCTAssertEqual(s2.txDelay,   3)
    }

    func testAPRSBeaconExtrasRoundTrip() {
        let map = MemoryMap()
        var s = map.aprsSettings()
        s.beaconIncludeSpeed = true
        s.beaconIncludeAlt   = true
        s.positionComment    = 3  // Returning
        s.decayAlgorithm     = true
        s.propPathing        = true
        map.setAPRSSettings(s)

        let s2 = map.aprsSettings()
        XCTAssertTrue(s2.beaconIncludeSpeed)
        XCTAssertTrue(s2.beaconIncludeAlt)
        XCTAssertEqual(s2.positionComment, 3)
        XCTAssertTrue(s2.decayAlgorithm)
        XCTAssertTrue(s2.propPathing)
    }

    // MARK: - D-STAR round-trip tests

    func testDSTARCallsignsRoundTrip() {
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.myCallsign  = "AI5OS"
        s.aBandUrCall = "CQCQCQ"
        s.aBandRPT1   = "W5KA   C"
        s.aBandRPT2   = "W5KA   G"
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertEqual(s2.myCallsign,  "AI5OS")
        XCTAssertEqual(s2.aBandUrCall, "CQCQCQ")
        XCTAssertEqual(s2.aBandRPT1,   "W5KA   C")
        XCTAssertEqual(s2.aBandRPT2,   "W5KA   G")
    }

    func testDSTARSpacePaddingStrippedOnRead() {
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.myCallsign = "AI5OS"   // 5 chars — written as "AI5OS   " (space-padded to 8)
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertEqual(s2.myCallsign, "AI5OS")  // trailing spaces stripped on read
    }

    func testDSTARInitFromEmptyDataDoesNotCrash() {
        let settings = DSTARSettings(from: Data())
        XCTAssertEqual(settings.autoReply, 0)
        XCTAssertEqual(settings.myCallsign, "")
    }

    func testDSTARBBandRPTRoundTrip() {
        // bBandRPT1 and bBandRPT2 share address 0x0337 (confirmed via wizard).
        // setDSTARSettings writes bBandRPT2 last, so it always wins. bBandRPT1 set alone
        // is overwritten by the subsequent bBandRPT2="" write; only test bBandRPT2.
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.bBandRPT2 = "W5KA   G"
        map.setDSTARSettings(s)
        XCTAssertEqual(map.dstarSettings().bBandRPT2, "W5KA   G")
    }

    func testDSTARDVOptionsRoundTrip() {
        // Confirmed offsets from Java bytecode (TXRX struct base = clone 0x1A00)
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.directReply   = true
        s.rxAFC         = true
        s.fmAutoDetOnDV = true
        s.autoReply     = 1   // On
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertTrue(s2.directReply)
        XCTAssertTrue(s2.rxAFC)
        XCTAssertTrue(s2.fmAutoDetOnDV)
        XCTAssertEqual(s2.autoReply, 1)
    }

    func testDSTARAutoReplyTimingRoundTrip() {
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.autoReplyTiming = 3   // 20 sec
        s.dataTxEndTiming = 2   // 1 sec
        s.emrVolume       = 25
        s.dataFrameOutput = 1   // Related to DSQ
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertEqual(s2.autoReplyTiming, 3)
        XCTAssertEqual(s2.dataTxEndTiming, 2)
        XCTAssertEqual(s2.emrVolume,       25)
        XCTAssertEqual(s2.dataFrameOutput, 1)
    }

    func testDSTARBreakInDisplayRoundTrip() {
        // Confirmed via wizard: rxBreakIn block is at 0x1A0D–0x1A10 (not 0x1A0A–0x1A0D as struct-derived)
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.rxBreakInDisplay    = 1   // All
        s.rxBreakInSizeSingle = 1   // Entire
        s.rxBreakInSizeDual   = 0   // Half
        s.rxBreakInHoldTime   = 3   // 10 sec
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertEqual(s2.rxBreakInDisplay,    1)
        XCTAssertEqual(s2.rxBreakInSizeSingle, 1)
        XCTAssertEqual(s2.rxBreakInSizeDual,   0)
        XCTAssertEqual(s2.rxBreakInHoldTime,   3)
    }

    func testDSTARCallsignAnnounceRoundTrip() {
        // Tentative: struct-derived offsets 0x1A0E/0x1A0F were wrong (taken by rxBreakInSizeSingle/Dual).
        // callsignAnnounce tentatively @ 0x1A11, standbyBeep @ 0x1A12 — TODO: verify via wizard.
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.callsignAnnounce = 4   // All
        s.standbyBeep      = true
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertEqual(s2.callsignAnnounce, 4)
        XCTAssertTrue(s2.standbyBeep)
    }

    func testDSTARBBandDoesNotOverlapABand() {
        // Ensure bBand writes don't corrupt the A-band block.
        // Note: bBandRPT1 and bBandRPT2 share address 0x0337 — bBandRPT2 (written last) wins.
        let map = MemoryMap()
        var s = map.dstarSettings()
        s.aBandRPT1 = "W5KA   C"
        s.aBandRPT2 = "W5KA   G"
        s.bBandRPT1 = "N5XYZ  C"
        s.bBandRPT2 = "N5XYZ  G"
        map.setDSTARSettings(s)

        let s2 = map.dstarSettings()
        XCTAssertEqual(s2.aBandRPT1, "W5KA   C")
        XCTAssertEqual(s2.aBandRPT2, "W5KA   G")
        // Shared field — bBandRPT2 written last, so both read back as "N5XYZ  G"
        XCTAssertEqual(s2.bBandRPT1, "N5XYZ  G")
        XCTAssertEqual(s2.bBandRPT2, "N5XYZ  G")
    }

    // MARK: - RadioSettings round-trip through a full-size blob

    func testRoundTripDoesNotCrash() {
        // Start with a blank map (0xFF blob) and mutate settings.
        let map = MemoryMap()
        var s = map.radioSettings()     // read from 0xFF blob — must not crash

        // Change several fields and write back
        s.beatShift      = true
        s.beep           = false
        s.beepVolume     = 7
        s.displayBrightness = 5
        s.language       = 1            // Japanese
        map.setRadioSettings(s)

        // Re-read and verify round-trip fidelity
        let s2 = map.radioSettings()
        XCTAssertTrue(s2.beatShift)
        XCTAssertFalse(s2.beep)
        XCTAssertEqual(s2.beepVolume, 7)
        XCTAssertEqual(s2.displayBrightness, 5)
        XCTAssertEqual(s2.language, 1)
    }

    func testRoundTripAllBoolFields() {
        let map = MemoryMap()
        var s = map.radioSettings()
        s.txInhibit        = true
        s.wxAlert          = true
        s.autoRepeaterShift = true
        s.toneBurstHold    = true
        s.voxEnabled       = true
        s.cwReverse        = true
        s.qsoLog           = true
        s.fmRadioEnabled   = true
        s.usbAudio         = true
        s.btEnabled        = true
        s.btAutoConnect    = true
        s.cursorShift      = true
        s.dtmfLock         = true
        s.micLock          = true
        s.volumeLock       = true
        s.audioTxMonitor   = true
        s.scanAutoBacklight = true
        s.scanWeatherAuto  = true
        map.setRadioSettings(s)

        let s2 = map.radioSettings()
        XCTAssertTrue(s2.txInhibit)
        XCTAssertTrue(s2.wxAlert)
        XCTAssertTrue(s2.cwReverse)
        XCTAssertTrue(s2.fmRadioEnabled)
        XCTAssertTrue(s2.btEnabled)
        XCTAssertTrue(s2.dtmfLock)
    }

    func testRoundTripUInt8Fields() {
        let map = MemoryMap()
        var s = map.radioSettings()
        s.ssbHighCut          = 3
        s.cwWidth             = 2
        s.amHighCut           = 2
        s.timeOutTimer        = 2
        s.micSensitivity      = 2
        s.scanResumeAnalog    = 4
        s.scanResumeDigital   = 3
        s.scanTimeRestart     = 2
        s.scanCarrierRestart  = 1
        s.priorityScan        = 2
        s.voxGain             = 8
        s.voxDelay            = 5
        s.voxHysteresis       = 3
        s.dtmfSpeed           = 1
        s.dtmfHold            = 3
        s.dtmfPause           = 6
        s.cwPitch             = 6
        s.recallMethod        = 1
        s.audioRecordingBand  = 2
        s.fmRadioAutoMute     = 1
        s.displayBacklight    = 2
        s.displayBacklightTimer = 1
        s.displayBrightness   = 2
        s.displaySingleBand   = 3
        s.displayMeterType    = 2
        s.displayBgColor      = 1
        s.audioBalance        = 7
        s.beepVolume          = 5
        s.voiceGuidance       = 3
        s.voiceGuidanceSpeed  = 2
        s.batterySaver        = 5
        s.autoPowerOff        = 3
        s.pf1Key              = 3
        s.pf2Key              = 5
        s.pf1MicKey           = 2
        s.pf2MicKey           = 4
        s.pf3MicKey           = 1
        s.speedUnit           = 1
        s.altitudeUnit        = 1
        s.tempUnit            = 1
        s.latLongUnit         = 2
        s.gridSquare          = 2
        s.interfaceType       = 1
        s.language            = 1
        s.batteryCharging     = 1
        s.callsignReadout     = 1
        s.infoBacklight       = 2
        s.aBandTxPower        = 2
        s.bBandTxPower        = 3
        map.setRadioSettings(s)

        let s2 = map.radioSettings()
        XCTAssertEqual(s2.timeOutTimer,       2)
        XCTAssertEqual(s2.ssbHighCut,         3)
        XCTAssertEqual(s2.cwWidth,            2)
        XCTAssertEqual(s2.amHighCut,          2)
        XCTAssertEqual(s2.micSensitivity,     2)
        XCTAssertEqual(s2.voxGain,            8)
        XCTAssertEqual(s2.cwPitch,            6)
        XCTAssertEqual(s2.displayBrightness,  2)
        XCTAssertEqual(s2.displaySingleBand,  3)
        XCTAssertEqual(s2.infoBacklight,      2)
        XCTAssertEqual(s2.audioBalance,       7)
        XCTAssertEqual(s2.beepVolume,         5)
        XCTAssertEqual(s2.voiceGuidanceSpeed, 2)
        XCTAssertEqual(s2.batterySaver,       5)
        XCTAssertEqual(s2.autoPowerOff,       3)
        XCTAssertEqual(s2.gridSquare,         2)
        XCTAssertEqual(s2.callsignReadout,    1)
        XCTAssertEqual(s2.aBandTxPower,       2)
        XCTAssertEqual(s2.bBandTxPower,       3)
        XCTAssertEqual(s2.language,           1)
    }

    func testEquatable() {
        let s1 = RadioSettings(from: Data())
        let s2 = RadioSettings(from: Data())
        XCTAssertEqual(s1, s2)

        // init(from: Data()) gives beep=false (0 from empty blob); set to true to differ
        var s3 = RadioSettings(from: Data())
        s3.beep = true
        XCTAssertNotEqual(s1, s3)
    }

    func testOptionLabelsNonEmpty() {
        XCTAssertFalse(RadioSettings.timeOutTimerOptions.isEmpty)
        XCTAssertFalse(RadioSettings.txPowerOptions.isEmpty)
        XCTAssertFalse(RadioSettings.voxDelayOptions.isEmpty)
        XCTAssertFalse(RadioSettings.languageOptions.isEmpty)
    }

    // MARK: - New fields: LED control, voice guidance volume, USB/PC interface, power-on message

    func testNewRadioFieldsRoundTrip() {
        let map = MemoryMap()
        var s = map.radioSettings()

        s.ledControlRx          = true
        s.ledControlFmRadio     = true
        s.voiceGuidanceVolume   = 3
        s.usbAudioOutputLevel   = 5
        s.detectOutSelect       = 1
        s.usbFunction           = 1
        s.pcOutputGpsInterface  = 1
        s.pcOutputAprsInterface = 1
        s.kissInterface         = 1
        s.dvDrInterface         = 1
        map.setRadioSettings(s)

        let s2 = map.radioSettings()
        XCTAssertTrue(s2.ledControlRx)
        XCTAssertTrue(s2.ledControlFmRadio)
        XCTAssertEqual(s2.voiceGuidanceVolume,   3)
        XCTAssertEqual(s2.usbAudioOutputLevel,   5)
        XCTAssertEqual(s2.detectOutSelect,       1)
        XCTAssertEqual(s2.usbFunction,           1)
        XCTAssertEqual(s2.pcOutputGpsInterface,  1)
        XCTAssertEqual(s2.pcOutputAprsInterface, 1)
        XCTAssertEqual(s2.kissInterface,         1)
        XCTAssertEqual(s2.dvDrInterface,         1)
    }

    func testPowerOnMessageRoundTrip() {
        let map = MemoryMap()
        var s = map.radioSettings()
        s.powerOnMessage = "TH-D75 READY"
        map.setRadioSettings(s)

        let s2 = map.radioSettings()
        XCTAssertEqual(s2.powerOnMessage, "TH-D75 READY")
    }

    func testPowerOnMessageTruncatesAt16() {
        let map = MemoryMap()
        var s = map.radioSettings()
        s.powerOnMessage = "ABCDEFGHIJKLMNOPQRSTUVWXYZ"  // 26 chars — must truncate to 16
        map.setRadioSettings(s)

        let s2 = map.radioSettings()
        XCTAssertEqual(s2.powerOnMessage.count, 16)
        XCTAssertEqual(s2.powerOnMessage, "ABCDEFGHIJKLMNOP")
    }

    func testNewRadioOptionLabels() {
        XCTAssertEqual(RadioSettings.voiceGuidanceVolumeOptions.count, 8)   // VOL Link + Level 1–7
        XCTAssertEqual(RadioSettings.usbAudioOutputLevelOptions.count, 7)   // Level 1–7
        XCTAssertEqual(RadioSettings.detectOutOptions.count, 3)             // AF / IF / Detect
        XCTAssertEqual(RadioSettings.usbFunctionOptions.count, 2)           // COM+AF/IF / Mass Storage
        XCTAssertEqual(RadioSettings.usbBtInterfaceOptions.count, 2)        // USB / Bluetooth
    }
}
