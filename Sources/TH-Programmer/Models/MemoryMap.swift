// MemoryMap.swift — Binary memory map parser and writer for TH-D74/D75
// Ported from CHIRP thd74.py (MEM_FORMAT bitwise layout)

import Foundation

// MARK: - Raw binary layout helpers

private extension Data {
    func uint8(at offset: Int) -> UInt8 {
        guard offset < count else { return 0 }
        return self[index(startIndex, offsetBy: offset)]
    }

    func uint32LE(at offset: Int) -> UInt32 {
        guard offset + 3 < count else { return 0 }
        let b0 = UInt32(self[index(startIndex, offsetBy: offset)])
        let b1 = UInt32(self[index(startIndex, offsetBy: offset + 1)])
        let b2 = UInt32(self[index(startIndex, offsetBy: offset + 2)])
        let b3 = UInt32(self[index(startIndex, offsetBy: offset + 3)])
        return b0 | (b1 << 8) | (b2 << 16) | (b3 << 24)
    }

    mutating func setUInt8(_ v: UInt8, at offset: Int) {
        guard offset < count else { return }
        self[index(startIndex, offsetBy: offset)] = v
    }

    mutating func setUInt32LE(_ v: UInt32, at offset: Int) {
        guard offset + 3 < count else { return }
        self[index(startIndex, offsetBy: offset)]     = UInt8(v & 0xFF)
        self[index(startIndex, offsetBy: offset + 1)] = UInt8((v >> 8) & 0xFF)
        self[index(startIndex, offsetBy: offset + 2)] = UInt8((v >> 16) & 0xFF)
        self[index(startIndex, offsetBy: offset + 3)] = UInt8((v >> 24) & 0xFF)
    }
}

// MARK: - Memory Map

/// Wraps the raw 0x7A300-byte memory blob and provides decoded channel access.
final class MemoryMap: @unchecked Sendable {

    var raw: Data

    init(data: Data) {
        precondition(data.count == MEMORY_SIZE, "Expected \(MEMORY_SIZE) bytes, got \(data.count)")
        self.raw = data
    }

    /// Create a blank (all-0xFF) memory map
    convenience init() {
        self.init(data: Data(repeating: 0xFF, count: MEMORY_SIZE))
    }

    nonisolated deinit {}

    // MARK: - .d74/.d75 file I/O

    /// Load from a .d74 or .d75 file (256-byte header + raw blob)
    static func load(from url: URL) throws -> MemoryMap {
        let fileData = try Data(contentsOf: url)
        guard fileData.count >= 256 + MEMORY_SIZE else {
            throw MemoryMapError.fileTooSmall(fileData.count)
        }
        let blob = fileData.subdata(in: 256..<(256 + MEMORY_SIZE))
        return MemoryMap(data: blob)
    }

    /// Save to a .d74 or .d75 file
    func save(to url: URL) throws {
        var out = D74_FILE_HEADER
        out.append(raw)
        try out.write(to: url)
    }

    // MARK: - Flag accessors (offset 0x2000, 4 bytes each)

    private func flagOffset(for number: Int) -> Int {
        return FLAGS_OFFSET + number * FLAG_STRUCT_SIZE
    }

    func usedByte(for number: Int) -> UInt8 {
        raw.uint8(at: flagOffset(for: number))
    }

    func isEmpty(number: Int) -> Bool {
        usedByte(for: number) == 0xFF
    }

    func isLockedOut(number: Int) -> Bool {
        let b = raw.uint8(at: flagOffset(for: number) + 1)
        return (b & 0x01) != 0  // lockout is bit 0
    }

    func group(for number: Int) -> Int {
        Int(raw.uint8(at: flagOffset(for: number) + 2))
    }

    // MARK: - Raw memory struct accessor

    /// Byte offset of memory struct for channel `number`
    /// Layout: memgroups[number / 6].memories[number % 6]
    /// Each group = 6 × 40 bytes + 16 bytes pad = 256 bytes
    private func memOffset(for number: Int) -> Int {
        let groupIndex = number / 6
        let indexInGroup = number % 6
        return MEMORIES_OFFSET + groupIndex * MEMORY_GROUP_SIZE + indexInGroup * MEMORY_STRUCT_SIZE
    }

    /// Byte offset of name for channel `number` in names array
    /// Call channels have a +5 adjustment
    private func nameOffset(for number: Int, isCallChan: Bool = false) -> Int {
        let adj = isCallChan ? 5 : 0
        return NAMES_OFFSET + (number + adj) * NAME_LENGTH
    }

    // MARK: - Channel decode

    func channel(number: Int) -> ChannelMemory {
        let extdNumber: String?
        if number >= 1000 {
            let extdIdx = number - 1000
            extdNumber = extdIdx < EXTD_NUMBERS.count ? EXTD_NUMBERS[extdIdx] : nil
        } else {
            extdNumber = nil
        }

        var mem = ChannelMemory(number: number, extdNumber: extdNumber)

        if isEmpty(number: number) {
            mem.empty = true
            if extdNumber != nil { mem.immutable.append("empty") }
            return mem
        }

        mem.empty = false
        let base = memOffset(for: number)
        let isCall = extdNumber?.contains("Call") ?? false

        // freq / offset (ul32 = unsigned little-endian 32-bit)
        mem.freq = raw.uint32LE(at: base)
        mem.offset = raw.uint32LE(at: base + 4)

        // Byte 8: tuning_step:4, split_tuning_step:3, unknown2:1
        let byte8 = raw.uint8(at: base + 8)
        let tsIdx = Int(byte8 & 0x0F)
        let stsIdx = Int((byte8 >> 4) & 0x07)
        mem.tuningStep = tsIdx < TUNE_STEPS.count ? TUNE_STEPS[tsIdx] : 5.0
        mem.splitTuningStep = stsIdx < TUNE_STEPS.count ? TUNE_STEPS[stsIdx] : 5.0

        // Byte 9: unknown3_0:1, mode:3, narrow:1, fine_mode:1, fine_step:2
        let byte9 = raw.uint8(at: base + 9)
        let modeIdx = Int((byte9 >> 1) & 0x07)
        mem.mode = RadioMode(rawValue: modeIdx) ?? .fm
        mem.narrow = ((byte9 >> 4) & 0x01) != 0
        mem.fineMode = ((byte9 >> 5) & 0x01) != 0
        mem.fineStep = Int((byte9 >> 6) & 0x03)

        // Byte 10: tone_mode:1, ctcss_mode:1, dtcs_mode:1, cross_mode:1,
        //          unknown4_0:1, split:1, duplex:2
        let byte10 = raw.uint8(at: base + 10)
        let toneModeBit  = (byte10 >> 0) & 0x01
        let ctcssModeBit = (byte10 >> 1) & 0x01
        let dtcsModeBit  = (byte10 >> 2) & 0x01
        let crossModeBit = (byte10 >> 3) & 0x01
        let splitBit     = (byte10 >> 5) & 0x01
        let duplexBits   = (byte10 >> 6) & 0x03

        if toneModeBit != 0 {
            mem.toneMode = .tone
        } else if ctcssModeBit != 0 {
            mem.toneMode = .tsql
        } else if dtcsModeBit != 0 {
            mem.toneMode = .dtcs
        } else if crossModeBit != 0 {
            mem.toneMode = .cross
        } else {
            mem.toneMode = .none
        }

        if splitBit != 0 {
            mem.duplex = .split
        } else {
            mem.duplex = DuplexMode(rawValue: Int(duplexBits)) ?? .simplex
        }

        // Byte 11: rtone index
        let rtoneIdx = Int(raw.uint8(at: base + 11))
        mem.rtone = rtoneIdx < CTCSS_TONES.count ? CTCSS_TONES[rtoneIdx] : 88.5

        // Byte 12: unknownctone:2, ctone:6
        let ctoneIdx = Int(raw.uint8(at: base + 12) & 0x3F)
        mem.ctone = ctoneIdx < CTCSS_TONES.count ? CTCSS_TONES[ctoneIdx] : 88.5

        // Byte 13: unknowndtcs:1, dtcs_code:7
        let dtcsIdx = Int(raw.uint8(at: base + 13) & 0x7F)
        mem.dtcs = dtcsIdx < DTCS_CODES.count ? DTCS_CODES[dtcsIdx] : 23

        // Byte 14: unknown5_1:2, cross_mode_mode:2, unknown5_2:2, dig_squelch:2
        let byte14 = raw.uint8(at: base + 14)
        let crossModeMode = Int((byte14 >> 2) & 0x03)
        mem.crossMode = CrossMode(rawValue: crossModeMode) ?? .dtcsToDtcs
        mem.digSquelch = Int((byte14 >> 6) & 0x03)

        // DV calls (bytes 15–22, 23–30, 31–38)
        if mem.mode.isDigital {
            mem.dvURCall  = decodeCall(raw, at: base + 15)
            mem.dvRPT1Call = decodeCall(raw, at: base + 23)
            mem.dvRPT2Call = decodeCall(raw, at: base + 31)

            // Byte 39: unknown9:1, dv_code:7
            mem.dvCode = Int(raw.uint8(at: base + 39) & 0x7F)

            // mode index 7 = DR (repeater mode)
            mem.dvRepeaterMode = (modeIdx == 7)
        }

        // Name
        let nOff = nameOffset(for: number, isCallChan: isCall)
        mem.name = decodeName(raw, at: nOff, length: NAME_LENGTH)

        // Skip / lockout
        mem.skip = isLockedOut(number: number)
        mem.group = group(for: number)

        // Immutable fields for special channels
        if extdNumber != nil {
            mem.immutable.append("empty")
        }
        if mem.isWX {
            mem.immutable.append(contentsOf: [
                "rtone","ctone","dtcs","rx_dtcs","tmode","cross_mode",
                "dtcs_polarity","skip","power","offset","mode","tuning_step"
            ])
        }
        if isCall && mem.mode.isDigital {
            mem.immutable.append("mode")
        }

        return mem
    }

    // MARK: - Channel encode

    func setChannel(_ mem: ChannelMemory) {
        let number = mem.number
        let isCall = mem.extdNumber?.contains("Call") ?? false
        let base = memOffset(for: number)
        let nOff = nameOffset(for: number, isCallChan: isCall)

        // Used flag
        raw.setUInt8(usedFlagValue(for: mem), at: flagOffset(for: number))

        if mem.empty {
            // lockout + group = 0, name = 0x00s, memory = 0xFF
            raw.setUInt8(0x00, at: flagOffset(for: number) + 1)
            raw.setUInt8(0x00, at: flagOffset(for: number) + 2)
            for i in 0..<NAME_LENGTH {
                raw.setUInt8(0x00, at: nOff + i)
            }
            for i in 0..<MEMORY_STRUCT_SIZE {
                raw.setUInt8(0xFF, at: base + i)
            }
            return
        }

        // Clear memory struct
        for i in 0..<MEMORY_STRUCT_SIZE {
            raw.setUInt8(0x00, at: base + i)
        }

        // freq / offset
        raw.setUInt32LE(mem.freq, at: base)
        raw.setUInt32LE(mem.offset, at: base + 4)

        // Byte 8
        let tsIdx = UInt8(TUNE_STEPS.firstIndex(of: mem.tuningStep) ?? 0)
        let stsIdx = UInt8(TUNE_STEPS.firstIndex(of: mem.splitTuningStep) ?? 0)
        raw.setUInt8(tsIdx | (stsIdx << 4), at: base + 8)

        // Byte 9
        let modeIdx: UInt8
        if mem.mode == .fm || mem.mode == .nfm { modeIdx = mem.mode == .nfm ? 6 : 0 }
        else { modeIdx = UInt8(mem.mode.rawValue) }
        let actualModeIdx = mem.dvRepeaterMode && mem.mode.isDigital ? UInt8(7) : modeIdx
        var byte9: UInt8 = (actualModeIdx & 0x07) << 1
        if mem.narrow { byte9 |= (1 << 4) }
        if mem.fineMode { byte9 |= (1 << 5) }
        byte9 |= UInt8(mem.fineStep & 0x03) << 6
        raw.setUInt8(byte9, at: base + 9)

        // Byte 10
        var byte10: UInt8 = 0
        switch mem.toneMode {
        case .tone:  byte10 |= 0x01
        case .tsql:  byte10 |= 0x02
        case .dtcs:  byte10 |= 0x04
        case .cross: byte10 |= 0x08
        case .none: break
        }
        if mem.duplex == .split {
            byte10 |= 0x20
        } else {
            byte10 |= UInt8((mem.duplex.rawValue & 0x03) << 6)
        }
        raw.setUInt8(byte10, at: base + 10)

        // Byte 11: rtone index
        let rtoneIdx = UInt8(CTCSS_TONES.firstIndex(of: mem.rtone) ?? 0)
        raw.setUInt8(rtoneIdx, at: base + 11)

        // Byte 12: ctone index (6 bits)
        let ctoneIdx = UInt8(CTCSS_TONES.firstIndex(of: mem.ctone) ?? 0) & 0x3F
        raw.setUInt8(ctoneIdx, at: base + 12)

        // Byte 13: dtcs index (7 bits)
        let dtcsIdx = UInt8(DTCS_CODES.firstIndex(of: mem.dtcs) ?? 0) & 0x7F
        raw.setUInt8(dtcsIdx, at: base + 13)

        // Byte 14: cross_mode_mode (bits 2-3), dig_squelch (bits 6-7)
        var byte14: UInt8 = UInt8(mem.crossMode.rawValue & 0x03) << 2
        byte14 |= UInt8(mem.digSquelch & 0x03) << 6
        raw.setUInt8(byte14, at: base + 14)

        // DV calls
        if mem.mode.isDigital {
            encodeCall(mem.dvURCall,   into: &raw, at: base + 15)
            encodeCall(mem.dvRPT1Call, into: &raw, at: base + 23)
            encodeCall(mem.dvRPT2Call, into: &raw, at: base + 31)
            raw.setUInt8(UInt8(mem.dvCode & 0x7F), at: base + 39)
        }

        // Name (16 bytes, padded with spaces)
        let nameBytes = mem.name.utf8.prefix(NAME_LENGTH)
        for (i, b) in nameBytes.enumerated() {
            raw.setUInt8(b, at: nOff + i)
        }
        for i in nameBytes.count..<NAME_LENGTH {
            raw.setUInt8(0x20, at: nOff + i)  // space-pad
        }

        // Flags: lockout + group
        var flagByte1 = raw.uint8(at: flagOffset(for: number) + 1) & 0xFE
        if mem.skip { flagByte1 |= 0x01 }
        raw.setUInt8(flagByte1, at: flagOffset(for: number) + 1)
        raw.setUInt8(UInt8(mem.group & 0xFF), at: flagOffset(for: number) + 2)
    }

    // MARK: - Group names

    func groupName(index: Int) -> String {
        let offset = NAMES_OFFSET + (GROUP_NAME_OFFSET + index) * NAME_LENGTH
        return decodeName(raw, at: offset, length: NAME_LENGTH)
    }

    func setGroupName(_ name: String, index: Int) {
        let offset = NAMES_OFFSET + (GROUP_NAME_OFFSET + index) * NAME_LENGTH
        let bytes = name.utf8.prefix(NAME_LENGTH)
        for (i, b) in bytes.enumerated() {
            raw.setUInt8(b, at: offset + i)
        }
        for i in bytes.count..<NAME_LENGTH {
            raw.setUInt8(0x20, at: offset + i)
        }
    }

    func allGroups() -> [ChannelGroup] {
        (0..<GROUP_COUNT).map { i in
            ChannelGroup(index: i, name: groupName(index: i))
        }
    }

    // MARK: - Helpers

    private func usedFlagValue(for mem: ChannelMemory) -> UInt8 {
        if mem.empty { return 0xFF }
        let freq = mem.duplex == .split ? mem.offset : mem.freq
        if freq < 150_000_000 { return 0x00 }
        if freq < 400_000_000 { return 0x01 }
        return 0x02
    }

    private func decodeCall(_ data: Data, at offset: Int) -> String {
        var result = ""
        for i in 0..<8 {
            let b = data.uint8(at: offset + i)
            if b == 0 { break }
            result.append(Character(UnicodeScalar(b)))
        }
        return result.isEmpty ? "CQCQCQ  " : result.padding(toLength: 8, withPad: " ", startingAt: 0)
    }

    private func encodeCall(_ call: String, into data: inout Data, at offset: Int) {
        let padded = call.prefix(8).padding(toLength: 8, withPad: "\0", startingAt: 0)
        for (i, c) in padded.utf8.enumerated() {
            data.setUInt8(c, at: offset + i)
        }
    }

    private func decodeName(_ data: Data, at offset: Int, length: Int) -> String {
        var bytes: [UInt8] = []
        for i in 0..<length {
            let b = data.uint8(at: offset + i)
            if b == 0 { break }
            bytes.append(b)
        }
        return String(bytes: bytes, encoding: .utf8)?
            .trimmingCharacters(in: .whitespaces) ?? ""
    }
}

// MARK: - Errors

enum MemoryMapError: Error, LocalizedError {
    case fileTooSmall(Int)
    case invalidHeader

    var errorDescription: String? {
        switch self {
        case .fileTooSmall(let size):
            return "File too small: \(size) bytes (expected at least \(256 + MEMORY_SIZE))"
        case .invalidHeader:
            return "Not a valid .d74/.d75 file"
        }
    }
}
