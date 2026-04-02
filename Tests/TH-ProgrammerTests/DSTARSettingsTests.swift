// DSTARSettingsTests.swift — Unit tests for DSTARSettings

import XCTest
@testable import TH_Programmer

final class DSTARSettingsTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Default values

    func testInitFromEmptyDataDefaults() {
        let s = DSTARSettings(from: Data())
        XCTAssertFalse(s.directReply)
        XCTAssertEqual(s.autoReplyTiming,   0)       // Immediate
        XCTAssertEqual(s.dataTxEndTiming,   0)       // Off
        XCTAssertEqual(s.emrVolume,         1)       // Minimum non-zero volume
        XCTAssertFalse(s.rxAFC)
        XCTAssertFalse(s.fmAutoDetOnDV)
        XCTAssertEqual(s.dataFrameOutput,   0)       // All
        // breakCall removed — transient runtime flag, not stored in file (cleared on power off)
        XCTAssertEqual(s.digitalSquelchType, 0)      // Off
        XCTAssertEqual(s.digitalCode,        0)      // Off
    }

    // MARK: - Option label counts

    func testAutoReplyTimingOptions() {
        // Immediate / 5 sec / 10 sec / 20 sec / 30 sec / 60 sec
        XCTAssertEqual(DSTARSettings.autoReplyTimingOptions.count, 6)
    }

    func testDataTxEndTimingOptions() {
        // Off / 0.5 sec / 1 sec / 1.5 sec / 2 sec
        XCTAssertEqual(DSTARSettings.dataTxEndTimingOptions.count, 5)
    }

    func testDataFrameOutputOptions() {
        // All / Related to DSQ / DATA Mode
        XCTAssertEqual(DSTARSettings.dataFrameOutputOptions.count, 3)
    }

    func testDigitalSquelchOptions() {
        // Off / Callsign Squelch / Code Squelch
        XCTAssertEqual(DSTARSettings.digitalSquelchOptions.count, 3)
    }

    func testDigitalCodeOptions() {
        // Off / 1 / 2 / 3 / 4 / 5
        XCTAssertEqual(DSTARSettings.digitalCodeOptions.count, 6)
    }

    // MARK: - Equatable

    func testEquatable() {
        let s1 = DSTARSettings(from: Data())
        let s2 = DSTARSettings(from: Data())
        XCTAssertEqual(s1, s2)

        var s3 = DSTARSettings(from: Data())
        s3.directReply = true
        XCTAssertNotEqual(s1, s3)

        var s4 = DSTARSettings(from: Data())
        s4.digitalSquelchType = 2
        XCTAssertNotEqual(s1, s4)
    }

    // MARK: - EMR Volume bounds

    func testEMRVolumeDefault() {
        let s = DSTARSettings(from: Data())
        XCTAssertGreaterThanOrEqual(s.emrVolume, 1)
        XCTAssertLessThanOrEqual(s.emrVolume, 50)
    }
}
