// AudioRingBufferTests.swift — Tests for the circular PCM buffer

import XCTest
@testable import TH_Programmer

final class AudioRingBufferTests: XCTestCase {

    nonisolated deinit {}

    func testWrite_read_basic() {
        let buf = AudioRingBuffer(capacity: 100)
        buf.write([1, 2, 3, 4, 5])
        XCTAssertEqual(buf.available, 5)
        let read = buf.read(maxCount: 5)
        XCTAssertEqual(read, [1, 2, 3, 4, 5])
        XCTAssertEqual(buf.available, 0)
    }

    func testRead_empty() {
        let buf = AudioRingBuffer(capacity: 100)
        XCTAssertEqual(buf.read(maxCount: 10), [])
    }

    func testRead_partialRead() {
        let buf = AudioRingBuffer(capacity: 100)
        buf.write([10, 20, 30])
        let read = buf.read(maxCount: 2)
        XCTAssertEqual(read, [10, 20])
        XCTAssertEqual(buf.available, 1)
    }

    func testReadPadded_padsWithZeros() {
        let buf = AudioRingBuffer(capacity: 100)
        buf.write([1, 2])
        let read = buf.readPadded(count: 5)
        XCTAssertEqual(read, [1, 2, 0, 0, 0])
    }

    func testOverflow_dropsOldest() {
        let buf = AudioRingBuffer(capacity: 4)
        buf.write([1, 2, 3, 4])
        buf.write([5, 6])
        // Buffer should contain [3, 4, 5, 6] — oldest dropped
        XCTAssertEqual(buf.available, 4)
        let read = buf.read(maxCount: 4)
        XCTAssertEqual(read, [3, 4, 5, 6])
    }

    func testFlush_clearsBuffer() {
        let buf = AudioRingBuffer(capacity: 100)
        buf.write([1, 2, 3])
        buf.flush()
        XCTAssertEqual(buf.available, 0)
        XCTAssertEqual(buf.read(maxCount: 10), [])
    }

    func testWrapAround_correctReadOrder() {
        let buf = AudioRingBuffer(capacity: 5)
        buf.write([1, 2, 3])
        _ = buf.read(maxCount: 2)  // read [1, 2], leaves [3]
        buf.write([4, 5, 6])       // buffer: [3, 4, 5, 6]
        let read = buf.read(maxCount: 4)
        XCTAssertEqual(read, [3, 4, 5, 6])
    }
}
