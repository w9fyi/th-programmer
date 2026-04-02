// ReflectorClientProtocol.swift — Abstract protocol for D-STAR reflector clients

import Foundation

/// Protocol abstracting DExtra and DCS reflector clients so the gateway
/// can work with either without caring about the underlying network protocol.
protocol ReflectorClientProtocol: AnyObject {
    var onVoiceFrame: ((DVFrame) -> Void)? { get set }
    var onHeaderReceived: ((String) -> Void)? { get set }
    var onStateChange: ((ReflectorConnectionState) -> Void)? { get set }
    var onError: ((String) -> Void)? { get set }
    var state: ReflectorConnectionState { get }

    func connect(hostname: String, module: Character, callsign: String, localModule: Character)
    func disconnect()
    func sendVoiceFrame(_ frame: DVFrame)
    func sendHeader(streamID: UInt16, myCallsign: String)
}
