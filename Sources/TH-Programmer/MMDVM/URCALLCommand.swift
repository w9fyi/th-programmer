// URCALLCommand.swift — Parse D-STAR URCALL field for link/unlink/info/echo commands

import Foundation

/// Parsed command from the 8-byte D-STAR YOUR/URCALL field.
enum URCALLCommand: Equatable, Sendable {

    /// Normal voice traffic — forward to reflector as usual.
    case voice

    /// Link to a reflector module (e.g. "REF001CL" -> link REF001 module C).
    case link(ReflectorTarget)

    /// Unlink from current reflector (e.g. "       U" or "REF001CU").
    case unlink

    /// Request reflector info (e.g. "       I").
    case info

    /// Echo test (e.g. "       E").
    case echo

    // MARK: - Parser

    /// Parse an 8-character URCALL string into a command.
    /// The input should be exactly 8 bytes from the D-STAR header YOUR field.
    /// Returns `.voice` for normal CQ calls or unrecognized patterns.
    static func parse(_ urcall: String) -> URCALLCommand {
        // Pad or truncate to exactly 8 characters
        let padded = urcall.padding(toLength: 8, withPad: " ", startingAt: 0)
        let trimmed = padded.trimmingCharacters(in: .whitespaces)

        // Empty or CQCQCQ — normal voice
        if trimmed.isEmpty || trimmed.hasPrefix("CQCQCQ") {
            return .voice
        }

        // Check for single-character commands at position 8 (7 spaces + command)
        // These are "       U", "       I", "       E"
        let prefix7 = String(padded.prefix(7))
        let lastChar = padded.last ?? " "

        if prefix7.trimmingCharacters(in: .whitespaces).isEmpty {
            switch lastChar {
            case "U":
                return .unlink
            case "I":
                return .info
            case "E":
                return .echo
            default:
                break
            }
        }

        // Check for link/unlink command: PREFIXnnnML or PREFIXnnnMU
        // Format: 3-char type + 3-digit number + 1-char module + L/U
        // Must be exactly 8 characters
        guard padded.count >= 8 else { return .voice }

        let typeStr = String(padded.prefix(3)).uppercased()
        guard let reflectorType = ReflectorTarget.ReflectorType(rawValue: typeStr) else {
            return .voice
        }

        let numberStr = String(padded.dropFirst(3).prefix(3))
        guard let number = Int(numberStr), number >= 1, number <= 999 else {
            return .voice
        }

        let moduleChar = Character(String(padded.dropFirst(6).prefix(1)).uppercased())
        guard moduleChar.isLetter, moduleChar.isUppercase else {
            return .voice
        }

        let commandChar = padded[padded.index(padded.startIndex, offsetBy: 7)]
        switch commandChar {
        case "L":
            let target = ReflectorTarget(type: reflectorType, number: number, module: moduleChar)
            return .link(target)
        case "U":
            return .unlink
        default:
            return .voice
        }
    }
}
