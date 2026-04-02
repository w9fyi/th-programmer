// ChannelMemory.swift — TH-D75 channel memory model

import Foundation

/// One memory channel, fully decoded from the radio's binary format.
struct ChannelMemory: Identifiable, Equatable {
    var id: Int { number }

    // Channel number: 0–999 regular, 1000+ extended
    var number: Int
    var extdNumber: String? = nil    // "WX1", "Priority", "VHF Call (A)", etc.

    var empty: Bool = true

    var freq: UInt32 = 146_000_000   // Hz
    var offset: UInt32 = 600_000     // Hz
    var duplex: DuplexMode = .simplex
    var tuningStep: Double = 5.0
    var splitTuningStep: Double = 5.0

    var mode: RadioMode = .fm
    var narrow: Bool = false

    var toneMode: ToneMode = .none
    var rtone: Double = 88.5
    var ctone: Double = 88.5
    var dtcs: Int = 23
    var crossMode: CrossMode = .dtcsToDtcs

    var skip: Bool = false
    var group: Int = 0
    var name: String = ""

    // D-STAR / DV
    var dvURCall: String = "CQCQCQ  "
    var dvRPT1Call: String = "        "
    var dvRPT2Call: String = "        "
    var dvCode: Int = 0
    var dvRepeaterMode: Bool = false  // "DR" mode (mode index 7)
    var digSquelch: Int = 0

    // Fine tuning
    var fineMode: Bool = false
    var fineStep: Int = 0

    var immutable: [String] = []

    /// True if this channel's number is in the extended range
    var isExtended: Bool { number >= 1000 }

    var isWX: Bool { extdNumber?.hasPrefix("WX") ?? false }
    var isCall: Bool { extdNumber?.contains("Call") ?? false }

    /// Display frequency as MHz string
    var freqMHz: String {
        String(format: "%.6g", Double(freq) / 1_000_000.0)
    }

    /// Display offset as kHz string
    var offsetKHz: String {
        String(format: "%.4g kHz", Double(offset) / 1_000.0)
    }

    static func empty(number: Int, extdNumber: String? = nil) -> ChannelMemory {
        var ch = ChannelMemory(number: number)
        ch.extdNumber = extdNumber
        ch.empty = true
        return ch
    }
}

/// One 30-channel group/bank
struct ChannelGroup: Identifiable {
    var id: Int { index }
    var index: Int
    var name: String
}
