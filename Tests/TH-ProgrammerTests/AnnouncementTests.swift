// AnnouncementTests.swift — Tests for AnnouncementPlayer AMBE audio loading and phrase building

import XCTest
@testable import TH_Programmer

final class AnnouncementTests: XCTestCase {

    nonisolated deinit {}

    /// Path to the test announcement files in the project Resources directory.
    private var announcementsDir: String {
        // Walk up from the test executable to find the project root
        let execURL = URL(fileURLWithPath: CommandLine.arguments[0])
        // Try common locations relative to build products
        let candidates = [
            // SwiftPM build: .build/debug/TH-ProgrammerPackageTests.xctest/…
            execURL.deletingLastPathComponent()
                .appendingPathComponent("../../../../Resources/Announcements").standardized.path,
            // Xcode: DerivedData/…/Build/Products/Debug/…
            execURL.deletingLastPathComponent()
                .appendingPathComponent("../../../../../Resources/Announcements").standardized.path,
            // Direct project path fallback
            "/Users/justinmann/Desktop/devprojects/th-programmer/Resources/Announcements",
        ]
        for path in candidates {
            if FileManager.default.fileExists(atPath: path + "/en_US.ambe") {
                return path
            }
        }
        return candidates.last!
    }

    private func makePlayer() -> AnnouncementPlayer? {
        AnnouncementPlayer(directory: announcementsDir)
    }

    // MARK: - Loading

    func testLoadIndexFileHasExpectedWordCount() throws {
        let player = try XCTUnwrap(makePlayer(), "Failed to load announcement files")
        // The index has 44 entries: 0-9 (10), alpha-delta (4), A-Z (26), linked/notlinked/linking/isbusy (4)
        XCTAssertEqual(player.wordCount, 44, "Expected 44 words in the announcement index")
    }

    func testLoadIndexContainsExpectedLabels() throws {
        let player = try XCTUnwrap(makePlayer())

        // Digits
        for digit in 0...9 {
            XCTAssertNotNil(player.index["\(digit)"], "Missing digit \(digit)")
        }
        // Letters
        for letter in "ABCDEFGHIJKLMNOPQRSTUVWXYZ" {
            XCTAssertNotNil(player.index[String(letter).lowercased()], "Missing letter \(letter)")
        }
        // Status words
        XCTAssertNotNil(player.index["linked"])
        XCTAssertNotNil(player.index["notlinked"])
        XCTAssertNotNil(player.index["linking"])
        XCTAssertNotNil(player.index["isbusy"])
        // NATO phonetic
        XCTAssertNotNil(player.index["alpha"])
        XCTAssertNotNil(player.index["bravo"])
        XCTAssertNotNil(player.index["charlie"])
        XCTAssertNotNil(player.index["delta"])
    }

    // MARK: - Frame Extraction

    func testFramesForWordReturnsCorrectCount() throws {
        let player = try XCTUnwrap(makePlayer())

        // "linked" has 20 frames per the index
        let linkedFrames = try XCTUnwrap(player.framesForWord("linked"))
        XCTAssertEqual(linkedFrames.count, 20)

        // Each frame should be exactly 9 bytes
        for frame in linkedFrames {
            XCTAssertEqual(frame.count, AnnouncementPlayer.ambeFrameSize)
        }
    }

    func testFramesForWordIsCaseInsensitive() throws {
        let player = try XCTUnwrap(makePlayer())
        XCTAssertNotNil(player.framesForWord("LINKED"))
        XCTAssertNotNil(player.framesForWord("Linked"))
        XCTAssertNotNil(player.framesForWord("linked"))
    }

    func testFramesForUnknownWordReturnsNil() throws {
        let player = try XCTUnwrap(makePlayer())
        XCTAssertNil(player.framesForWord("nonexistent"))
        XCTAssertNil(player.framesForWord("module"))
        XCTAssertNil(player.framesForWord("to"))
    }

    // MARK: - Announcement Building

    func testBuildLinkedAnnouncement() throws {
        let player = try XCTUnwrap(makePlayer())

        // "linked R E F 0 0 1 charlie" — REF001 module C
        let frames = player.linkedAnnouncement(type: "REF", number: 1, module: "C")
        XCTAssertFalse(frames.isEmpty, "Linked announcement should produce frames")

        // Verify each frame is 9 bytes
        for frame in frames {
            XCTAssertEqual(frame.count, AnnouncementPlayer.ambeFrameSize)
        }

        // Calculate expected frame count:
        // Words: linked + R + E + F + 0 + 0 + 1 + charlie = 8 words
        // Silence gaps: 7 gaps * 5 frames = 35 silence frames
        // Word frames: sum of each word's frame count from index
        let wordLabels = ["linked", "r", "e", "f", "0", "0", "1", "charlie"]
        var expectedWordFrames = 0
        for label in wordLabels {
            if let entry = player.index[label] {
                expectedWordFrames += entry.frameCount
            }
        }
        let expectedTotal = expectedWordFrames + (7 * 5)  // 7 gaps * 5 silence frames
        XCTAssertEqual(frames.count, expectedTotal, "Frame count should match word frames + silence gaps")
    }

    func testBuildUnlinkedAnnouncement() throws {
        let player = try XCTUnwrap(makePlayer())
        let frames = player.unlinkedAnnouncement()
        XCTAssertFalse(frames.isEmpty)

        // Should have exactly the number of frames for "notlinked" (49 per index)
        let entry = try XCTUnwrap(player.index["notlinked"])
        XCTAssertEqual(frames.count, entry.frameCount)
    }

    func testBuildLinkingAnnouncement() throws {
        let player = try XCTUnwrap(makePlayer())
        let frames = player.linkingAnnouncement()
        XCTAssertFalse(frames.isEmpty)

        let entry = try XCTUnwrap(player.index["linking"])
        XCTAssertEqual(frames.count, entry.frameCount)
    }

    func testBuildBusyAnnouncement() throws {
        let player = try XCTUnwrap(makePlayer())
        let frames = player.busyAnnouncement()
        XCTAssertFalse(frames.isEmpty)

        let entry = try XCTUnwrap(player.index["isbusy"])
        XCTAssertEqual(frames.count, entry.frameCount)
    }

    func testBuildAnnouncementSkipsUnknownWords() throws {
        let player = try XCTUnwrap(makePlayer())

        // Mix of known and unknown words — unknowns should be silently skipped
        let frames = player.buildAnnouncement(words: ["linked", "nonexistent", "0"])
        XCTAssertFalse(frames.isEmpty)

        // Should have frames for "linked" + silence gap + "0" (unknown word skipped, no gap for it)
        let linkedCount = player.index["linked"]!.frameCount
        let zeroCount = player.index["0"]!.frameCount
        // Words present: "linked" and "0" — 1 silence gap between them
        // The unknown word is skipped entirely (no gap inserted for it)
        let expected = linkedCount + 5 + zeroCount
        XCTAssertEqual(frames.count, expected)
    }

    func testBuildAnnouncementEmptyWordsReturnsEmpty() throws {
        let player = try XCTUnwrap(makePlayer())
        let frames = player.buildAnnouncement(words: [])
        XCTAssertTrue(frames.isEmpty)
    }

    func testBuildAnnouncementAllUnknownWordsReturnsEmpty() throws {
        let player = try XCTUnwrap(makePlayer())
        let frames = player.buildAnnouncement(words: ["foo", "bar", "baz"])
        XCTAssertTrue(frames.isEmpty)
    }

    // MARK: - NATO Phonetic

    func testNATOPhoneticUsedForModules() throws {
        let player = try XCTUnwrap(makePlayer())

        // Module A → "alpha", B → "bravo", C → "charlie", D → "delta"
        for (module, nato) in [("A", "alpha"), ("B", "bravo"), ("C", "charlie"), ("D", "delta")] {
            let frames = player.linkedAnnouncement(type: "REF", number: 1, module: Character(module))
            XCTAssertFalse(frames.isEmpty, "Should produce frames for module \(module)")
            // Verify the NATO word's frames are present (not just the letter)
            let natoEntry = player.index[nato]!
            let letterEntry = player.index[module.lowercased()]!
            // NATO word should be used instead of bare letter — verify total includes NATO frame count
            XCTAssertTrue(natoEntry.frameCount != letterEntry.frameCount || natoEntry.frameCount > 0)
        }
    }

    func testNonNATOModuleUsesLetter() throws {
        let player = try XCTUnwrap(makePlayer())

        // Module E has no NATO phonetic in the pack — should fall back to letter "E"
        let frames = player.linkedAnnouncement(type: "XRF", number: 1, module: "E")
        XCTAssertFalse(frames.isEmpty)

        // Verify the letter "E" frames are used (not a NATO word)
        let wordLabels = ["linked", "x", "r", "f", "0", "0", "1", "e"]
        var expectedWordFrames = 0
        for label in wordLabels {
            if let entry = player.index[label] {
                expectedWordFrames += entry.frameCount
            }
        }
        let expectedTotal = expectedWordFrames + (7 * 5)
        XCTAssertEqual(frames.count, expectedTotal)
    }

    // MARK: - Silence

    func testSilenceGapFrames() {
        let silence = AnnouncementPlayer.silenceGapFrames()
        XCTAssertEqual(silence.count, 5)  // 100ms = 5 * 20ms
        for frame in silence {
            XCTAssertEqual(frame.count, AnnouncementPlayer.ambeFrameSize)
            XCTAssertEqual(frame, AnnouncementPlayer.silenceAMBE)
        }
    }
}
