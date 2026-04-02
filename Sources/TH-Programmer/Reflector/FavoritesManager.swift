// FavoritesManager.swift — Persistence and management of reflector favorites

import Foundation

/// Manages saved reflector favorites with UserDefaults persistence.
@MainActor
final class FavoritesManager: ObservableObject {

    nonisolated deinit {}

    @Published var favorites: [ReflectorFavorite] = []

    private let userDefaultsKey = "ReflectorFavorites"

    init() {
        load()
    }

    // MARK: - Public API

    func add(target: ReflectorTarget, label: String) {
        // Don't add duplicates (same type + number + module)
        guard !favorites.contains(where: {
            $0.type == target.type && $0.number == target.number && $0.module == target.module
        }) else { return }

        let favorite = ReflectorFavorite(
            type: target.type,
            number: target.number,
            module: target.module,
            label: label
        )
        favorites.append(favorite)
        save()
    }

    func remove(id: UUID) {
        favorites.removeAll { $0.id == id }
        save()
    }

    func updateLastUsed(target: ReflectorTarget) {
        guard let index = favorites.firstIndex(where: {
            $0.type == target.type && $0.number == target.number && $0.module == target.module
        }) else { return }
        favorites[index].lastUsed = Date()
        save()
    }

    // MARK: - Persistence

    func save() {
        guard let data = try? JSONEncoder().encode(favorites) else { return }
        UserDefaults.standard.set(data, forKey: userDefaultsKey)
    }

    func load() {
        guard let data = UserDefaults.standard.data(forKey: userDefaultsKey),
              let decoded = try? JSONDecoder().decode([ReflectorFavorite].self, from: data) else { return }
        favorites = decoded
    }
}
