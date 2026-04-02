// RepeaterEntryTests.swift — Unit tests for RepeaterEntry JSON decoding and helpers

import XCTest
@testable import TH_Programmer

final class RepeaterEntryTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Sample JSON fixture (matches RepeaterBook API shape)

    private let sampleJSON = """
    {
      "count": 2,
      "results": [
        {
          "Callsign": "W5YI",
          "Frequency": "146.880",
          "Input Freq": "146.280",
          "Offset": "-0.600",
          "CTCSS": "100.0",
          "TSQ": null,
          "City": "Austin",
          "State": "Texas",
          "Use": "OPEN"
        },
        {
          "Callsign": "N5XYZ",
          "Frequency": "444.500",
          "Input Freq": "449.500",
          "Offset": "+5.000",
          "CTCSS": null,
          "TSQ": null,
          "City": "Round Rock",
          "State": "Texas",
          "Use": "OPEN"
        }
      ]
    }
    """

    private var entries: [RepeaterEntry] {
        let data = sampleJSON.data(using: .utf8)!
        let response = try! JSONDecoder().decode(RepeaterBookResponse.self, from: data)
        return response.results!
    }

    // MARK: - Decoding

    func testDecodeCount() {
        XCTAssertEqual(entries.count, 2)
    }

    func testDecodeCallsign() {
        XCTAssertEqual(entries[0].callsign, "W5YI")
        XCTAssertEqual(entries[1].callsign, "N5XYZ")
    }

    func testDecodeFrequency() {
        XCTAssertEqual(entries[0].frequency, "146.880")
        XCTAssertEqual(entries[1].frequency, "444.500")
    }

    func testDecodeCity() {
        XCTAssertEqual(entries[0].city, "Austin")
        XCTAssertEqual(entries[1].city, "Round Rock")
    }

    func testDecodeCTCSS() {
        XCTAssertEqual(entries[0].ctcssTone, "100.0")
        XCTAssertNil(entries[1].ctcssTone)
    }

    func testDecodeUse() {
        XCTAssertEqual(entries[0].use, "OPEN")
    }

    func testSelectedDefaultsTrue() {
        XCTAssertTrue(entries[0].selected)
        XCTAssertTrue(entries[1].selected)
    }

    // MARK: - Derived helpers (minus repeater)

    func testRxFreqHz() {
        XCTAssertEqual(entries[0].rxFreqHz, 146_880_000)
    }

    func testTxFreqHzFromInputFreq() {
        XCTAssertEqual(entries[0].txFreqHz, 146_280_000)
    }

    func testOffsetHz() {
        XCTAssertEqual(entries[0].offsetHz, 600_000)
    }

    func testDuplexModeMinus() {
        XCTAssertEqual(entries[0].duplexMode, .minus)
    }

    func testCtcssHz() {
        XCTAssertEqual(entries[0].ctcssHz, 100.0, accuracy: 0.01)
    }

    func testChannelToneModeWithCTCSS() {
        XCTAssertEqual(entries[0].channelToneMode, .tone)
    }

    func testChannelToneModeWithoutCTCSS() {
        XCTAssertEqual(entries[1].channelToneMode, .none)
    }

    func testCtcssHzNone() {
        XCTAssertEqual(entries[1].ctcssHz, 0.0, accuracy: 0.01)
    }

    // MARK: - Derived helpers (plus repeater)

    func testRxFreqHzPlus() {
        XCTAssertEqual(entries[1].rxFreqHz, 444_500_000)
    }

    func testTxFreqHzPlus() {
        XCTAssertEqual(entries[1].txFreqHz, 449_500_000)
    }

    func testOffsetHzPlus() {
        XCTAssertEqual(entries[1].offsetHz, 5_000_000)
    }

    func testDuplexModePlus() {
        XCTAssertEqual(entries[1].duplexMode, .plus)
    }

    // MARK: - Identifiable id

    func testIDIsCallsignPlusFrequency() {
        let e = entries[0]
        XCTAssertEqual(e.id, "W5YI146.880")
    }

    // MARK: - Label

    func testLabelContainsCallsign() {
        XCTAssertTrue(entries[0].label.contains("W5YI"))
    }

    func testLabelContainsFrequency() {
        XCTAssertTrue(entries[0].label.contains("146.880"))
    }

    // MARK: - RepeaterBookResponse with empty results

    func testEmptyResultsDecoding() {
        let json = """
        {"count":0,"results":[]}
        """
        let response = try! JSONDecoder().decode(
            RepeaterBookResponse.self,
            from: json.data(using: .utf8)!
        )
        XCTAssertEqual(response.count, 0)
        XCTAssertEqual(response.results?.count, 0)
    }

    func testNullResultsDecoding() {
        let json = """
        {"count":null}
        """
        let response = try! JSONDecoder().decode(
            RepeaterBookResponse.self,
            from: json.data(using: .utf8)!
        )
        XCTAssertNil(response.count)
        XCTAssertNil(response.results)
    }

    // MARK: - txFreqHz fallback when inputFreq is absent

    func testTxFreqFallbackToOffset() {
        let json = """
        {"count":1,"results":[{
            "Callsign":"K5TRA",
            "Frequency":"147.120",
            "Offset":"+0.600",
            "City":"Austin",
            "State":"Texas"
        }]}
        """
        let response = try! JSONDecoder().decode(
            RepeaterBookResponse.self,
            from: json.data(using: .utf8)!
        )
        let e = response.results![0]
        XCTAssertNil(e.inputFreq)
        // Should fall back to rxFreqHz + offset
        XCTAssertEqual(e.rxFreqHz, 147_120_000)
        XCTAssertEqual(e.txFreqHz, 147_720_000)
        XCTAssertEqual(e.duplexMode, .plus)
    }
}
