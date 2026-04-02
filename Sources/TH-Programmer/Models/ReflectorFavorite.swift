// ReflectorFavorite.swift — Saved reflector favorites

import Foundation

/// A saved reflector target with a user-provided label.
struct ReflectorFavorite: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    var type: ReflectorTarget.ReflectorType
    var number: Int
    var module: Character
    var label: String
    var lastUsed: Date?

    init(id: UUID = UUID(), type: ReflectorTarget.ReflectorType, number: Int, module: Character, label: String, lastUsed: Date? = nil) {
        self.id = id
        self.type = type
        self.number = number
        self.module = module
        self.label = label
        self.lastUsed = lastUsed
    }

    /// Display name like "REF001 A".
    var reflectorName: String {
        "\(type.rawValue)\(String(format: "%03d", number)) \(module)"
    }

    /// Convert to a ReflectorTarget.
    var target: ReflectorTarget {
        ReflectorTarget(type: type, number: number, module: module)
    }

    // MARK: - Codable (Character needs manual coding)

    enum CodingKeys: String, CodingKey {
        case id, type, number, module, label, lastUsed
    }

    init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        id = try container.decode(UUID.self, forKey: .id)
        type = try container.decode(ReflectorTarget.ReflectorType.self, forKey: .type)
        number = try container.decode(Int.self, forKey: .number)
        let moduleString = try container.decode(String.self, forKey: .module)
        module = moduleString.first ?? "A"
        label = try container.decode(String.self, forKey: .label)
        lastUsed = try container.decodeIfPresent(Date.self, forKey: .lastUsed)
    }

    func encode(to encoder: Encoder) throws {
        var container = encoder.container(keyedBy: CodingKeys.self)
        try container.encode(id, forKey: .id)
        try container.encode(type, forKey: .type)
        try container.encode(number, forKey: .number)
        try container.encode(String(module), forKey: .module)
        try container.encode(label, forKey: .label)
        try container.encodeIfPresent(lastUsed, forKey: .lastUsed)
    }
}
