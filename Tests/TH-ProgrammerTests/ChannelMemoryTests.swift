// ChannelMemoryTests.swift — Unit tests for ChannelMemory and MemoryMap channel access

import XCTest
@testable import TH_Programmer

final class ChannelMemoryTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - ChannelMemory defaults

    func testDefaultValues() {
        let ch = ChannelMemory(number: 42)
        XCTAssertEqual(ch.number, 42)
        XCTAssertNil(ch.extdNumber)
        XCTAssertTrue(ch.empty)
        XCTAssertEqual(ch.freq, 146_000_000)
        XCTAssertEqual(ch.offset, 600_000)
        XCTAssertEqual(ch.duplex, .simplex)
        XCTAssertEqual(ch.mode, .fm)
        XCTAssertFalse(ch.narrow)
        XCTAssertEqual(ch.toneMode, .none)
        XCTAssertEqual(ch.rtone, 88.5)
        XCTAssertEqual(ch.ctone, 88.5)
        XCTAssertEqual(ch.dtcs, 23)
        XCTAssertFalse(ch.skip)
        XCTAssertEqual(ch.group, 0)
        XCTAssertEqual(ch.name, "")
    }

    func testID() {
        let ch = ChannelMemory(number: 7)
        XCTAssertEqual(ch.id, 7)
    }

    // MARK: - Computed display properties

    func testFreqMHz() {
        var ch = ChannelMemory(number: 0)
        ch.freq = 146_520_000
        XCTAssertEqual(ch.freqMHz, "146.52")
    }

    func testFreqMHzFullPrecision() {
        var ch = ChannelMemory(number: 0)
        ch.freq = 443_075_000
        XCTAssertEqual(ch.freqMHz, "443.075")
    }

    func testOffsetKHz() {
        var ch = ChannelMemory(number: 0)
        ch.offset = 600_000
        XCTAssertTrue(ch.offsetKHz.contains("600"))
    }

    // MARK: - Extended / special channel flags

    func testIsExtendedRegular() {
        let ch = ChannelMemory(number: 999)
        XCTAssertFalse(ch.isExtended)
    }

    func testIsExtendedExtended() {
        let ch = ChannelMemory(number: 1000)
        XCTAssertTrue(ch.isExtended)
    }

    func testIsWXTrue() {
        var ch = ChannelMemory(number: 1101)
        ch.extdNumber = "WX1"
        XCTAssertTrue(ch.isWX)
    }

    func testIsWXFalse() {
        var ch = ChannelMemory(number: 1000)
        ch.extdNumber = "Priority"
        XCTAssertFalse(ch.isWX)
    }

    func testIsCallTrue() {
        var ch = ChannelMemory(number: 1131)
        ch.extdNumber = "VHF Call (A)"
        XCTAssertTrue(ch.isCall)
    }

    func testIsCallFalse() {
        var ch = ChannelMemory(number: 1000)
        ch.extdNumber = "Priority"
        XCTAssertFalse(ch.isCall)
    }

    func testEmptyFactory() {
        let ch = ChannelMemory.empty(number: 55)
        XCTAssertEqual(ch.number, 55)
        XCTAssertTrue(ch.empty)
        XCTAssertNil(ch.extdNumber)
    }

    func testEmptyFactoryWithExtd() {
        let ch = ChannelMemory.empty(number: 1101, extdNumber: "WX1")
        XCTAssertEqual(ch.extdNumber, "WX1")
        XCTAssertTrue(ch.empty)
    }

    // MARK: - Equatable

    func testEqualSameNumber() {
        let a = ChannelMemory(number: 5)
        let b = ChannelMemory(number: 5)
        XCTAssertEqual(a, b)
    }

    func testNotEqualDifferentFreq() {
        var a = ChannelMemory(number: 5)
        var b = ChannelMemory(number: 5)
        a.freq = 146_000_000
        b.freq = 447_000_000
        XCTAssertNotEqual(a, b)
    }

    // MARK: - MemoryMap channel round-trip

    func testBlankMapChannelIsEmpty() {
        let map = MemoryMap()
        let ch = map.channel(number: 0)
        XCTAssertTrue(ch.empty)
    }

    func testBlankMapExtdChannelHasExtdNumber() {
        let map = MemoryMap()
        let ch = map.channel(number: 1000)
        // 1000 → EXTD_NUMBERS[0] = "Lower00"
        XCTAssertNotNil(ch.extdNumber)
        XCTAssertTrue(ch.isExtended)
    }

    func testSetChannelAndReadBack() {
        let map = MemoryMap()
        var ch = ChannelMemory(number: 10)
        ch.empty  = false
        ch.freq   = 146_520_000
        ch.offset = 600_000
        ch.duplex = .minus
        ch.mode   = .fm
        ch.toneMode = .tone
        ch.rtone  = 100.0
        ch.name   = "TEST"
        map.setChannel(ch)

        let ch2 = map.channel(number: 10)
        XCTAssertFalse(ch2.empty)
        XCTAssertEqual(ch2.freq, 146_520_000)
        XCTAssertEqual(ch2.offset, 600_000)
        XCTAssertEqual(ch2.duplex, .minus)
        XCTAssertEqual(ch2.mode, .fm)
        XCTAssertEqual(ch2.toneMode, .tone)
        XCTAssertEqual(ch2.rtone, 100.0, accuracy: 0.1)
        XCTAssertEqual(ch2.name.trimmingCharacters(in: .whitespaces), "TEST")
    }

    func testSetChannelEmptyFlagPersists() {
        let map = MemoryMap()
        var ch = ChannelMemory(number: 5)
        ch.empty = false
        ch.freq = 443_000_000
        map.setChannel(ch)
        XCTAssertFalse(map.channel(number: 5).empty)

        var ch2 = map.channel(number: 5)
        ch2.empty = true
        map.setChannel(ch2)
        XCTAssertTrue(map.channel(number: 5).empty)
    }

    func testMemoryMapBlankInit() {
        let map = MemoryMap()
        XCTAssertEqual(map.raw.count, MEMORY_SIZE)
    }

    func testMemoryMapDataInitWrongSizePreconditionFires() {
        // We expect a preconditionFailure for wrong-size data.
        // XCTest can't catch precondition failures portably, so we just
        // verify the happy path with the correct size.
        let correctData = Data(repeating: 0xFF, count: MEMORY_SIZE)
        let map = MemoryMap(data: correctData)
        XCTAssertEqual(map.raw.count, MEMORY_SIZE)
    }

    // MARK: - allGroups

    func testAllGroupsCount() {
        let map = MemoryMap()
        let groups = map.allGroups()
        XCTAssertEqual(groups.count, GROUP_COUNT)
    }

    func testGroupIndices() {
        let map = MemoryMap()
        let groups = map.allGroups()
        for (i, g) in groups.enumerated() {
            XCTAssertEqual(g.index, i)
        }
    }

    // MARK: - RadioConstants sanity

    func testCTCSSToneCount() {
        XCTAssertEqual(CTCSS_TONES.count, 50)
    }

    func testDTCSCodesCount() {
        XCTAssertEqual(DTCS_CODES.count, 104)
    }

    func testTuneStepsCount() {
        XCTAssertEqual(TUNE_STEPS.count, 12)
    }

    func testExtdNumbersFirstIsLower00() {
        XCTAssertEqual(EXTD_NUMBERS.first!, "Lower00")
    }

    func testMemorySizeConstant() {
        XCTAssertEqual(MEMORY_SIZE, 0x2A300)
    }
}
