// RadioConstants.swift — TH-D75 radio-specific constants, ported from CHIRP thd74.py

import Foundation

// CTCSS tones (50 values), same as chirp_common.TONES
let CTCSS_TONES: [Double] = [
    67.0, 69.3, 71.9, 74.4, 77.0, 79.7, 82.5, 85.4, 88.5, 91.5,
    94.8, 97.4, 100.0, 103.5, 107.2, 110.9, 114.8, 118.8, 123.0, 127.3,
    131.8, 136.5, 141.3, 146.2, 151.4, 156.7, 159.8, 162.2, 165.5, 167.9,
    171.3, 173.8, 177.3, 179.9, 183.5, 186.2, 189.9, 192.8, 196.6, 199.5,
    203.5, 206.5, 210.7, 218.1, 225.7, 229.1, 233.6, 241.8, 250.3, 254.1
]

// DTCS codes (104 values), same as chirp_common.DTCS_CODES
let DTCS_CODES: [Int] = [
    23, 25, 26, 31, 32, 36, 43, 47, 51, 53, 54, 65, 71, 72, 73, 74,
    114, 115, 116, 122, 125, 131, 132, 134, 143, 145, 152, 155, 156,
    162, 165, 172, 174, 205, 212, 223, 225, 226, 243, 244, 245, 246,
    251, 252, 255, 261, 263, 265, 266, 271, 274, 306, 311, 315, 325,
    331, 332, 343, 346, 351, 356, 364, 365, 371, 411, 412, 413, 423,
    431, 432, 445, 446, 452, 454, 455, 462, 464, 465, 466, 503, 506,
    516, 523, 526, 532, 546, 565, 606, 612, 624, 627, 631, 632, 654,
    662, 664, 703, 712, 723, 731, 732, 734, 743, 754
]

// Duplex modes
enum DuplexMode: Int, CaseIterable, Identifiable {
    case simplex = 0
    case plus = 1
    case minus = 2
    case split = 3

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .simplex: return ""
        case .plus: return "+"
        case .minus: return "-"
        case .split: return "Split"
        }
    }
}

// Tuning steps (12 values)
let TUNE_STEPS: [Double] = [5.0, 6.25, 8.33, 9.0, 10.0, 12.5, 15.0, 20.0, 25.0, 30.0, 50.0, 100.0]

// Modulation modes
enum RadioMode: Int, CaseIterable, Identifiable {
    case fm = 0
    case dv = 1
    case am = 2
    case lsb = 3
    case usb = 4
    case cw = 5
    case nfm = 6
    case dr = 7  // DR mode (same index as DV, used for repeater mode)

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .fm: return "FM"
        case .dv: return "DV"
        case .am: return "AM"
        case .lsb: return "LSB"
        case .usb: return "USB"
        case .cw: return "CW"
        case .nfm: return "NFM"
        case .dr: return "DR"
        }
    }

    var isDigital: Bool { self == .dv || self == .dr }
}

// Tone modes
enum ToneMode: Int, CaseIterable, Identifiable {
    case none = 0
    case tone = 1
    case tsql = 2
    case dtcs = 3
    case cross = 4

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none: return "None"
        case .tone: return "Tone"
        case .tsql: return "TSQL"
        case .dtcs: return "DTCS"
        case .cross: return "Cross"
        }
    }
}

// Cross modes (4 values)
enum CrossMode: Int, CaseIterable, Identifiable {
    case dtcsToDtcs = 0        // "DTCS->"   (only DTCS squelch decode)
    case toneToTone = 1        // "Tone->DTCS" -- wait, let me recheck
    case dtcsToTone = 2
    case toneTone = 3

    var id: Int { rawValue }
    var label: String {
        // From CHIRP: CROSS_MODES = ['DTCS->', 'Tone->DTCS', 'DTCS->Tone', 'Tone->Tone']
        switch self {
        case .dtcsToDtcs: return "DTCS->"
        case .toneToTone: return "Tone->DTCS"
        case .dtcsToTone: return "DTCS->Tone"
        case .toneTone: return "Tone->Tone"
        }
    }
}

// Digital squelch modes
enum DigitalSquelch: Int, CaseIterable, Identifiable {
    case none = 0
    case code = 1
    case callsign = 2

    var id: Int { rawValue }
    var label: String {
        switch self {
        case .none: return ""
        case .code: return "Code"
        case .callsign: return "Callsign"
        }
    }
}

// Extended channel numbers (special channels after #999)
// Ported from CHIRP EXTD_NUMBERS
let EXTD_NUMBERS: [String?] = {
    var result: [String?] = []
    // Lower00..Lower49 / Upper00..Upper49 (interleaved: i%2==1 => Upper, else Lower)
    for i in 0..<100 {
        let name = (i % 2 == 1) ? "Upper\(String(format: "%02d", i / 2))" : "Lower\(String(format: "%02d", i / 2))"
        result.append(name)
    }
    result.append("Priority")
    for i in 0..<10 { result.append("WX\(i + 1)") }
    for _ in 0..<20 { result.append(nil) }  // buffer
    for name in CALL_CHAN_NAMES { result.append(name) }
    return result
}()

let CALL_CHAN_NAMES = [
    "VHF Call (A)",
    "VHF Call (D)",
    "220M Call (A)",
    "220M Call (D)",
    "UHF Call (A)",
    "UHF Call (D)"
]

// .d75 / .d74 file header (256 bytes)
// Matches D74_FILE_HEADER in thd74.py
let D74_FILE_HEADER: Data = {
    var d = Data()
    // "MCP-D74\xFF V1.03\xFF\xFF\xFF"
    d += Data("MCP-D74".utf8)
    d.append(0xFF)
    d += Data("V1.03".utf8)
    d.append(contentsOf: [0xFF, 0xFF, 0xFF])
    // "TH-D74" + 10×0xFF
    d += Data("TH-D74".utf8)
    d.append(contentsOf: Array(repeating: UInt8(0xFF), count: 10))
    // 0x00 + 15×0xFF
    d.append(0x00)
    d.append(contentsOf: Array(repeating: UInt8(0xFF), count: 15))
    // 5×16 bytes of 0xFF
    d.append(contentsOf: Array(repeating: UInt8(0xFF), count: 5 * 16))
    // "K2" + 14×0xFF
    d += Data("K2".utf8)
    d.append(contentsOf: Array(repeating: UInt8(0xFF), count: 14))
    // 7×16 bytes of 0xFF
    d.append(contentsOf: Array(repeating: UInt8(0xFF), count: 7 * 16))
    // Pad to exactly 256 bytes
    while d.count < 256 { d.append(0xFF) }
    return Data(d.prefix(256))
}()

let MEMORY_SIZE = 0x2A300  // total raw memory blob size (TH-D75: 172,800 bytes)
let FLAGS_OFFSET = 0x2000
let MEMORIES_OFFSET = 0x4000
let NAMES_OFFSET = 0x10000
let GROUP_NAME_OFFSET = 1152  // index in names array where group names start
let CHANNEL_COUNT = 1000
let TOTAL_CHANNEL_SLOTS = 1200
let GROUP_COUNT = 30
let MEMORY_STRUCT_SIZE = 40
let NAME_LENGTH = 16
let FLAG_STRUCT_SIZE = 4
let MEMORY_GROUP_SIZE = 256  // 6 memories (240) + 16 pad
