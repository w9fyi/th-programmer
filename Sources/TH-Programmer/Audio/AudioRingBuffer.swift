// AudioRingBuffer.swift — Lock-protected circular buffer for PCM audio samples

import Foundation

/// Thread-safe circular buffer for Int16 PCM samples.
/// Producer (decode thread) writes, consumer (audio render thread) reads.
final class AudioRingBuffer: @unchecked Sendable {

    nonisolated deinit {}

    private let capacity: Int
    private var buffer: [Int16]
    private var readIndex: Int = 0
    private var writeIndex: Int = 0
    private var count: Int = 0
    private var lock = os_unfair_lock()

    /// Create a ring buffer with the given capacity in samples.
    /// Default: 8000 samples = 1 second at 8kHz.
    init(capacity: Int = 8000) {
        self.capacity = capacity
        self.buffer = [Int16](repeating: 0, count: capacity)
    }

    /// Number of samples available to read.
    var available: Int {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        return count
    }

    /// Write samples into the buffer. Drops oldest samples if full.
    func write(_ samples: [Int16]) {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        for sample in samples {
            buffer[writeIndex] = sample
            writeIndex = (writeIndex + 1) % capacity

            if count == capacity {
                // Overwrite oldest — advance read pointer
                readIndex = (readIndex + 1) % capacity
            } else {
                count += 1
            }
        }
    }

    /// Read up to `maxCount` samples from the buffer.
    /// Returns fewer samples if not enough are available.
    func read(maxCount: Int) -> [Int16] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        let toRead = Swift.min(maxCount, count)
        guard toRead > 0 else { return [] }

        var result = [Int16](repeating: 0, count: toRead)
        for i in 0..<toRead {
            result[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= toRead
        return result
    }

    /// Read exactly `count` samples, zero-padding if not enough are available.
    func readPadded(count requested: Int) -> [Int16] {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }

        var result = [Int16](repeating: 0, count: requested)
        let toRead = Swift.min(requested, count)
        for i in 0..<toRead {
            result[i] = buffer[readIndex]
            readIndex = (readIndex + 1) % capacity
        }
        count -= toRead
        return result
    }

    /// Discard all buffered samples.
    func flush() {
        os_unfair_lock_lock(&lock)
        defer { os_unfair_lock_unlock(&lock) }
        readIndex = 0
        writeIndex = 0
        count = 0
    }
}
