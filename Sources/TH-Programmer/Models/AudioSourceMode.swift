// AudioSourceMode.swift — Audio routing mode for software codec gateway

import Foundation

/// Selects where audio is routed in Software Codec mode.
enum AudioSourceMode: String, CaseIterable, Identifiable, Sendable {
    case macDefault = "Mac Audio"
    case radioUSB = "Radio USB"
    case radioBluetooth = "Radio Bluetooth"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .macDefault:
            return "Use the Mac's built-in or selected audio devices."
        case .radioUSB:
            return "Route audio through the TH-D75 USB audio interface."
        case .radioBluetooth:
            return "Route audio through the TH-D75 Bluetooth audio."
        }
    }
}
