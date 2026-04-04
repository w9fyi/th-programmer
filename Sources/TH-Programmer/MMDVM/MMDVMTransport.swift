// MMDVMTransport.swift — Protocol for MMDVM serial/RFCOMM transports

import Foundation

/// Connection state shared by all MMDVM transport implementations.
enum MMDVMTransportState: Equatable, Sendable {
    case disconnected
    case connecting(String)
    case connected(String)
    case error(String)
}

/// Abstract transport for MMDVM frame I/O.
/// Implementations: MMDVMSerialTransport (POSIX /dev/cu.*), RFCOMMTransport (direct IOBluetooth).
protocol MMDVMTransport: AnyObject, Sendable {
    var onStateChange: (@Sendable (MMDVMTransportState) -> Void)? { get set }
    var onDataReceived: (@Sendable (Data) -> Void)? { get set }

    func open(port: RadioSerialPort) throws
    func close()
    func send(_ data: Data) throws
    func setDTR(_ enabled: Bool) throws
}
