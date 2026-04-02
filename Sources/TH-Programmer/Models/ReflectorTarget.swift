// ReflectorTarget.swift — D-STAR reflector connection model

import Foundation

/// Represents a D-STAR reflector connection target.
struct ReflectorTarget: Equatable, Sendable {

    enum ReflectorType: String, CaseIterable, Identifiable, Codable, Sendable {
        case ref = "REF"
        case xrf = "XRF"
        case dcs = "DCS"
        case xlx = "XLX"

        var id: String { rawValue }
    }

    var type: ReflectorType = .ref
    var number: Int = 1          // 1–999
    var module: Character = "A"  // A–Z

    /// The 8-character UR call string for a link request.
    /// Format: "REFnnnML" where nnn=3-digit number, M=module, L=literal 'L'.
    var urCallString: String {
        let prefix = type.rawValue
        let num = String(format: "%03d", max(1, min(999, number)))
        return "\(prefix)\(num)\(module)L"
    }

    /// 8-char UR call to unlink from any reflector (7 spaces + U).
    static let unlinkCall = "       U"

    /// 8-char UR call to query reflector info (7 spaces + I).
    static let infoCall   = "       I"

    /// Validate that number is 1–999 and module is A–Z.
    var isValid: Bool {
        number >= 1 && number <= 999 &&
        module.isLetter && module.isUppercase
    }
}
