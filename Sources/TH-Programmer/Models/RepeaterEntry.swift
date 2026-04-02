// RepeaterEntry.swift — RepeaterBook API model

import Foundation

struct RepeaterEntry: Identifiable, Decodable {
    // Coding keys match the RepeaterBook JSON field names exactly
    enum CodingKeys: String, CodingKey {
        case callsign     = "Callsign"
        case frequency    = "Frequency"
        case inputFreq    = "Input Freq"
        case offset       = "Offset"
        case ctcssTone    = "CTCSS"
        case tsqTone      = "TSQ"
        case city         = "City"
        case state        = "State"
        case use          = "Use"
    }

    let callsign:  String
    let frequency: String   // output freq e.g. "146.880"
    let inputFreq: String?  // input freq  e.g. "146.280"
    let offset:    String?  // e.g. "-0.600" or "+0.600"
    let ctcssTone: String?  // TX CTCSS tone e.g. "100.0"  (may be null)
    let tsqTone:   String?  // RX CTCSS tone
    let city:      String
    let state:     String
    let use:       String?  // "OPEN" / "CLOSED"

    var id: String { callsign + frequency }
    var selected: Bool = true  // not from JSON, set in UI

    // MARK: - Derived helpers

    /// Output frequency in Hz (0 if unparseable)
    var rxFreqHz: UInt32 {
        UInt32((Double(frequency) ?? 0) * 1_000_000)
    }

    /// Input/transmit frequency in Hz
    var txFreqHz: UInt32 {
        if let s = inputFreq, let v = Double(s) {
            return UInt32(v * 1_000_000)
        }
        // Fall back: apply offset to output frequency
        let offHz = Int32((Double(offset ?? "0") ?? 0) * 1_000_000)
        return UInt32(max(0, Int64(rxFreqHz) + Int64(offHz)))
    }

    /// Offset magnitude in Hz (always positive)
    var offsetHz: UInt32 {
        abs(Int64(txFreqHz) - Int64(rxFreqHz)) > 0
            ? UInt32(abs(Int64(txFreqHz) - Int64(rxFreqHz)))
            : 600_000
    }

    /// Duplex direction
    var duplexMode: DuplexMode {
        if txFreqHz > rxFreqHz { return .plus }
        if txFreqHz < rxFreqHz { return .minus }
        return .simplex
    }

    /// TX CTCSS tone in Hz (0 if none)
    var ctcssHz: Double {
        if let s = ctcssTone, let v = Double(s) { return v }
        return 0
    }

    /// ToneMode for ChannelMemory
    var channelToneMode: ToneMode {
        ctcssHz > 0 ? .tone : .none
    }

    /// Human-readable label for the list
    var label: String {
        let tone = ctcssHz > 0 ? String(format: "%.1f Hz", ctcssHz) : "No tone"
        let dir  = offset ?? ""
        return "\(frequency) \(dir)  \(callsign)  \(city)  \(tone)"
    }

    // Decodable — selected is not in JSON so needs custom init
    init(from decoder: Decoder) throws {
        let c      = try decoder.container(keyedBy: CodingKeys.self)
        callsign   = try c.decode(String.self, forKey: .callsign)
        frequency  = try c.decode(String.self, forKey: .frequency)
        inputFreq  = try c.decodeIfPresent(String.self, forKey: .inputFreq)
        offset     = try c.decodeIfPresent(String.self, forKey: .offset)
        ctcssTone  = try c.decodeIfPresent(String.self, forKey: .ctcssTone)
        tsqTone    = try c.decodeIfPresent(String.self, forKey: .tsqTone)
        city       = try c.decode(String.self, forKey: .city)
        state      = try c.decode(String.self, forKey: .state)
        use        = try c.decodeIfPresent(String.self, forKey: .use)
        selected   = true
    }
}

struct RepeaterBookResponse: Decodable {
    let count:   Int?
    let results: [RepeaterEntry]?
}
