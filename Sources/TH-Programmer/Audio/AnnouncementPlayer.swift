// AnnouncementPlayer.swift — Loads pre-recorded AMBE audio segments and
// concatenates them into D-STAR voice announcements.
//
// The AMBE files originate from ircDDBGateway (Pi-Star). Format:
//   .ambe file: 4-byte "AMBE" header + sequential 9-byte AMBE frames
//   .indx file: tab-separated lines — label \t frame_offset \t frame_count

import Foundation

/// Loads an AMBE announcement pack and builds phrase sequences from individual words.
final class AnnouncementPlayer: @unchecked Sendable {

    /// One entry from the index file.
    struct IndexEntry {
        let label: String
        let frameOffset: Int
        let frameCount: Int
    }

    /// Parsed index entries keyed by lowercase label.
    private(set) var index: [String: IndexEntry] = [:]

    /// Raw AMBE data (after the 4-byte header).
    private let ambeData: Data

    /// Size of one AMBE frame in bytes.
    static let ambeFrameSize = 9

    /// Size of the file header ("AMBE").
    static let fileHeaderSize = 4

    /// NATO phonetic alphabet mapping for module letters.
    static let natoPhonetic: [Character: String] = [
        "A": "alpha", "B": "bravo", "C": "charlie", "D": "delta",
        // Only alpha-delta are in the ircDDBGateway pack.
        // Letters E-Z fall back to individual letter pronunciation.
    ]

    // MARK: - Init

    /// Load announcement data from .ambe and .indx files at the given directory path.
    /// - Parameter directory: Path to directory containing en_US.ambe and en_US.indx
    init?(directory: String) {
        let ambeURL = URL(fileURLWithPath: directory).appendingPathComponent("en_US.ambe")
        let indxURL = URL(fileURLWithPath: directory).appendingPathComponent("en_US.indx")

        guard let rawAmbe = try? Data(contentsOf: ambeURL),
              let indxText = try? String(contentsOf: indxURL, encoding: .utf8) else {
            return nil
        }

        // Validate AMBE header
        guard rawAmbe.count >= Self.fileHeaderSize,
              rawAmbe[0] == 0x41, rawAmbe[1] == 0x4D,  // "AM"
              rawAmbe[2] == 0x42, rawAmbe[3] == 0x45    // "BE"
        else {
            return nil
        }

        self.ambeData = rawAmbe.dropFirst(Self.fileHeaderSize)

        // Parse index
        for line in indxText.components(separatedBy: .newlines) {
            let parts = line.split(separator: "\t", omittingEmptySubsequences: false)
            guard parts.count >= 3,
                  let offset = Int(parts[1]),
                  let count = Int(parts[2]),
                  count > 0 else {
                continue
            }
            let label = String(parts[0])
            guard !label.isEmpty else { continue }
            index[label.lowercased()] = IndexEntry(label: label, frameOffset: offset, frameCount: count)
        }
    }

    /// Convenience init that searches for the Announcements directory
    /// relative to the executable or in common locations.
    convenience init?() {
        // Try relative to executable (for .app bundle)
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0]).deletingLastPathComponent()
        let bundleResources = execURL.appendingPathComponent("../Resources/Announcements").standardized.path
        if FileManager.default.fileExists(atPath: bundleResources + "/en_US.ambe") {
            self.init(directory: bundleResources)
            return
        }

        // Try Bundle.main.resourcePath (may work for some SwiftPM layouts)
        if let resourcePath = Bundle.main.resourcePath {
            let bundlePath = resourcePath + "/Announcements"
            if FileManager.default.fileExists(atPath: bundlePath + "/en_US.ambe") {
                self.init(directory: bundlePath)
                return
            }
        }

        // Try the project Resources directory (development)
        let devPath = execURL.appendingPathComponent("../../Resources/Announcements").standardized.path
        if FileManager.default.fileExists(atPath: devPath + "/en_US.ambe") {
            self.init(directory: devPath)
            return
        }

        return nil
    }

    // MARK: - Frame Extraction

    /// Get the AMBE frames for a single word/label.
    /// Returns nil if the label is not in the index.
    func framesForWord(_ label: String) -> [Data]? {
        guard let entry = index[label.lowercased()] else { return nil }

        let startByte = entry.frameOffset * Self.ambeFrameSize
        let endByte = startByte + (entry.frameCount * Self.ambeFrameSize)

        guard endByte <= ambeData.count else { return nil }

        var frames: [Data] = []
        frames.reserveCapacity(entry.frameCount)
        for i in 0..<entry.frameCount {
            let offset = startByte + (i * Self.ambeFrameSize)
            let frame = ambeData[offset..<(offset + Self.ambeFrameSize)]
            frames.append(Data(frame))
        }
        return frames
    }

    // MARK: - Announcement Building

    /// Build an announcement from a sequence of word labels.
    /// Unknown words are silently skipped. A 100ms silence gap (5 frames)
    /// is inserted between each word for natural pacing.
    func buildAnnouncement(words: [String]) -> [Data] {
        var allFrames: [Data] = []

        for (i, word) in words.enumerated() {
            guard let wordFrames = framesForWord(word) else { continue }
            allFrames.append(contentsOf: wordFrames)

            // Insert silence gap between words (not after the last one)
            if i < words.count - 1 {
                let silenceFrames = Self.silenceGapFrames()
                allFrames.append(contentsOf: silenceFrames)
            }
        }

        return allFrames
    }

    /// Build a "linked to reflector" announcement.
    /// Example: REF001 module C → ["linked", "R", "E", "F", "0", "0", "1", "charlie"]
    func linkedAnnouncement(type: String, number: Int, module: Character) -> [Data] {
        var words = ["linked"]
        // Spell out the reflector type letter by letter
        for char in type.uppercased() {
            words.append(String(char))
        }
        // Spell out the number digit by digit
        let digits = String(format: "%03d", number)
        for char in digits {
            words.append(String(char))
        }
        // Module: use NATO phonetic if available, else the letter
        if let nato = Self.natoPhonetic[Character(module.uppercased())] {
            words.append(nato)
        } else {
            words.append(String(module).uppercased())
        }
        return buildAnnouncement(words: words)
    }

    /// Build an "unlinked" announcement.
    func unlinkedAnnouncement() -> [Data] {
        buildAnnouncement(words: ["notlinked"])
    }

    /// Build a "linking" announcement.
    func linkingAnnouncement() -> [Data] {
        buildAnnouncement(words: ["linking"])
    }

    /// Build an "is busy" announcement.
    func busyAnnouncement() -> [Data] {
        buildAnnouncement(words: ["isbusy"])
    }

    // MARK: - Silence

    /// D-STAR AMBE silence frame (same as DExtraProtocol.silenceAMBE).
    static let silenceAMBE = Data([0x9E, 0x8D, 0x32, 0x88, 0x26, 0x1A, 0x3F, 0x61, 0xE8])

    /// Generate 5 silence frames (100ms gap at 20ms per frame).
    static func silenceGapFrames() -> [Data] {
        Array(repeating: silenceAMBE, count: 5)
    }

    /// Number of words loaded in the index.
    var wordCount: Int { index.count }
}
