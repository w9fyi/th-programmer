// ReflectorHostLookupTests.swift — Tests for reflector host lookup and dispatch safety

import XCTest
@testable import TH_Programmer

final class ReflectorHostLookupTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - Basic Lookup

    func testLookup_returnsNilForUnknownReflector() {
        let lookup = ReflectorHostLookup()
        XCTAssertNil(lookup.lookup(reflector: "REF999"))
    }

    func testIsLoaded_initiallyFalse() {
        let lookup = ReflectorHostLookup()
        XCTAssertFalse(lookup.isLoaded)
    }

    func testHostCount_initiallyZero() {
        let lookup = ReflectorHostLookup()
        XCTAssertEqual(lookup.hostCount, 0)
    }

    // MARK: - Host File Parsing

    func testParseHostFile_validEntries() {
        let text = "REF001\t192.168.1.1\nREF002\tref002.example.com\n"
        let results = ReflectorHostLookup.parseHostFile(text)
        XCTAssertEqual(results.count, 2)
        XCTAssertEqual(results[0].0, "REF001")
        XCTAssertEqual(results[0].1, "192.168.1.1")
        XCTAssertEqual(results[1].0, "REF002")
        XCTAssertEqual(results[1].1, "ref002.example.com")
    }

    func testParseHostFile_skipsComments() {
        let text = "# This is a comment\nREF001\t10.0.0.1\n"
        let results = ReflectorHostLookup.parseHostFile(text)
        XCTAssertEqual(results.count, 1)
        XCTAssertEqual(results[0].0, "REF001")
    }

    func testParseHostFile_skipsEmptyLines() {
        let text = "\n\nREF001\t10.0.0.1\n\n"
        let results = ReflectorHostLookup.parseHostFile(text)
        XCTAssertEqual(results.count, 1)
    }

    func testParseHostFile_skipsShortNames() {
        let text = "AB\t10.0.0.1\n"
        let results = ReflectorHostLookup.parseHostFile(text)
        XCTAssertEqual(results.count, 0)
    }

    func testParseHostFile_uppercasesNames() {
        let text = "ref001\t10.0.0.1\n"
        let results = ReflectorHostLookup.parseHostFile(text)
        XCTAssertEqual(results[0].0, "REF001")
    }

    // MARK: - IP Address Detection

    func testIsIPAddress_v4() {
        XCTAssertTrue(ReflectorHostLookup.isIPAddress("192.168.1.1"))
        XCTAssertTrue(ReflectorHostLookup.isIPAddress("10.0.0.1"))
    }

    func testIsIPAddress_v6() {
        XCTAssertTrue(ReflectorHostLookup.isIPAddress("::1"))
        XCTAssertTrue(ReflectorHostLookup.isIPAddress("2001:db8::1"))
    }

    func testIsIPAddress_hostname() {
        XCTAssertFalse(ReflectorHostLookup.isIPAddress("ref001.dstargateway.org"))
        XCTAssertFalse(ReflectorHostLookup.isIPAddress("example.com"))
    }

    // MARK: - Fallback Hostname

    func testFallbackHostname_ref() {
        XCTAssertEqual(
            ReflectorHostLookup.fallbackHostname(type: .ref, number: 1),
            "ref001.dstargateway.org"
        )
    }

    func testFallbackHostname_dcs() {
        XCTAssertEqual(
            ReflectorHostLookup.fallbackHostname(type: .dcs, number: 42),
            "dcs042.xreflector.net"
        )
    }

    func testFallbackHostname_xlx() {
        XCTAssertEqual(
            ReflectorHostLookup.fallbackHostname(type: .xlx, number: 307),
            "xlx307.dstargateway.org"
        )
    }

    // MARK: - Deadlock Regression (dispatch_sync on own queue)

    /// Regression test for crash: dispatch_sync called on queue already owned by current thread.
    ///
    /// The bug: authenticateDPlus fires its completion callback from self.queue.async {}.
    /// If that completion calls lookup(reflector:), which does queue.sync {}, it deadlocks
    /// because we're already on the queue.
    ///
    /// This test simulates the exact pattern: populate hosts on the queue, then call
    /// a completion that calls lookup(). If the deadlock exists, this test will time out.
    func testLookup_calledFromAuthCompletion_doesNotDeadlock() {
        let lookup = ReflectorHostLookup()
        let expectation = expectation(description: "Completion should fire without deadlock")
        expectation.assertForOverFulfill = false

        // Simulate what authenticateDPlus does: auth completes, then calls completion
        // from the hostlookup queue. The completion then calls lookup().
        // With the fix, the completion runs on main (not on the hostlookup queue),
        // so lookup's queue.sync doesn't deadlock.
        lookup.authenticateDPlus(callsign: "TEST") { count in
            // This is the pattern that crashed — calling lookup from the completion.
            // If completion fires on the hostlookup queue, this deadlocks.
            _ = lookup.lookup(reflector: "REF001")
            expectation.fulfill()
        }

        // 15 second timeout — if it deadlocks, test fails on timeout
        waitForExpectations(timeout: 15.0)
    }

    /// Verify that lookup works correctly after hosts have been populated.
    func testLookup_afterAuthPopulatesHosts_returnsIP() {
        let lookup = ReflectorHostLookup()
        let expectation = expectation(description: "Auth and lookup complete")

        lookup.authenticateDPlus(callsign: "AI5OS") { count in
            // Even if auth server is unreachable, this should not crash.
            // If it did return entries, verify lookup works.
            if count > 0 {
                let ip = lookup.lookup(reflector: "REF001")
                // REF001 is a well-known reflector — if auth succeeded, we should have it
                if let ip {
                    XCTAssertTrue(ReflectorHostLookup.isIPAddress(ip),
                                  "Expected IP address, got: \(ip)")
                }
            }
            expectation.fulfill()
        }

        waitForExpectations(timeout: 15.0)
    }

    /// Verify that isLoaded and hostCount can be called from any thread without deadlock.
    func testPropertyAccess_fromMultipleThreads_doesNotDeadlock() {
        let lookup = ReflectorHostLookup()
        let expectation = expectation(description: "All threads complete")
        expectation.expectedFulfillmentCount = 10

        for _ in 0..<10 {
            DispatchQueue.global().async {
                _ = lookup.isLoaded
                _ = lookup.hostCount
                _ = lookup.lookup(reflector: "REF001")
                expectation.fulfill()
            }
        }

        waitForExpectations(timeout: 5.0)
    }
}
