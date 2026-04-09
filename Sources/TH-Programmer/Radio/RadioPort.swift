// RadioPort.swift — Abstraction over serial port and direct RFCOMM for radio I/O
//
// Both USB (SerialPort) and Bluetooth (RFCOMMPort) implement this protocol.
// THD75LiveConnection and THD75Connection use it to send CAT commands
// without caring about the underlying transport.

import Foundation

/// Synchronous radio I/O interface. Implementations must be safe to call
/// from a single background thread (not required to be thread-safe across
/// multiple threads — callers serialize access).
protocol RadioPort: AnyObject {
    /// Open the connection. Parameters are hints — RFCOMM ignores baud/flow.
    func open(baudRate: Int32, hardwareFlowControl: Bool, twoStopBits: Bool) throws

    /// Write data synchronously.
    func write(_ data: Data) throws

    /// Read exactly `count` bytes, blocking up to `timeout`.
    func read(count: Int, timeout: TimeInterval) throws -> Data

    /// Read up to `maxCount` bytes within `timeout`. Returns what's available.
    func readAvailable(maxCount: Int, timeout: TimeInterval) throws -> Data

    /// Read one line (up to \r or \n), blocking up to `timeout`.
    func readLine(timeout: TimeInterval) throws -> String

    /// Discard any buffered input.
    func flushInput()

    /// Close the connection.
    func close()

    /// Non-blocking health check.
    func isHealthy() -> Bool

    /// Change baud rate (no-op for RFCOMM).
    func setBaudRate(_ rate: Int32, hardwareFlowControl: Bool, twoStopBits: Bool) throws
}
