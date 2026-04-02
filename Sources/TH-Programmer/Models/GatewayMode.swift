// GatewayMode.swift — Gateway operating mode for the reflector tab

import Foundation

/// Operating mode for the D-STAR reflector gateway.
enum GatewayMode: String, CaseIterable, Identifiable, Sendable {
    case software = "Software Codec"
    case mmdvmTerminal = "MMDVM Terminal"

    var id: String { rawValue }

    var description: String {
        switch self {
        case .software:
            return "Mac handles AMBE codec and audio. No radio needed."
        case .mmdvmTerminal:
            return "TH-D75 in terminal mode (Menu 650). Radio handles codec and audio."
        }
    }
}
