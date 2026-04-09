// RadioModel.swift — Model-specific protocol constants for TH-D74 vs TH-D75

import Foundation

/// Detected radio model — controls protocol branching for clone and live CAT.
enum RadioModel: Sendable {
    case d74
    case d75

    init(idResponse: String) {
        if idResponse.contains("TH-D75") {
            self = .d75
        } else {
            self = .d74
        }
    }

    /// MCP clone image size in 256-byte blocks.
    /// D74: 675 blocks (from CHIRP thd74.py — unverified by us).
    /// D75: 1955 pages (hardware-verified via thd75 reference library).
    var cloneBlocks: Int {
        switch self {
        case .d74: return 675
        case .d75: return 1955
        }
    }

    /// MCP clone image size in bytes.
    var cloneImageSize: Int { cloneBlocks * 256 }

    /// Baud rate for MCP binary data transfer (after 0M handshake).
    /// D74 switches to 57600 (CHIRP behavior — unverified by us).
    /// D75 stays at 9600 — 57600 crashes it into MCP error mode
    /// (confirmed by thd75 reference library).
    var cloneBaudRate: Int32 {
        switch self {
        case .d74: return 57600
        case .d75: return 9600
        }
    }

    /// Whether to switch baud after the 0M echo.
    var cloneSwitchesBaud: Bool {
        switch self {
        case .d74: return true
        case .d75: return false
        }
    }
}
