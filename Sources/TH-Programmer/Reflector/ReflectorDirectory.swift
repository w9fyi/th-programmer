// ReflectorDirectory.swift — Searchable D-STAR reflector directory

import Foundation

/// Fetches and caches D-STAR reflector status from public APIs.
@MainActor
final class ReflectorDirectory: ObservableObject {

    nonisolated deinit {}

    // MARK: - Model

    struct ReflectorInfo: Identifiable, Sendable {
        let id: String              // "REF001"
        let type: ReflectorTarget.ReflectorType
        let number: Int
        let hostname: String
        let modules: [ModuleInfo]
        let country: String
        let description: String
    }

    struct ModuleInfo: Identifiable, Sendable {
        var id: String { "\(letter)" }
        let letter: Character
        let connectedCount: Int
        let lastHeard: String?
        let lastHeardTime: Date?
    }

    // MARK: - Published State

    @Published var reflectors: [ReflectorInfo] = []
    @Published var isLoading: Bool = false
    @Published var errorMessage: String?
    @Published var searchText: String = ""
    @Published var typeFilter: ReflectorTarget.ReflectorType?

    var filteredReflectors: [ReflectorInfo] {
        var result = reflectors
        if let filter = typeFilter {
            result = result.filter { $0.type == filter }
        }
        if !searchText.isEmpty {
            let query = searchText.uppercased()
            result = result.filter {
                $0.id.uppercased().contains(query)
                || $0.country.uppercased().contains(query)
                || $0.description.uppercased().contains(query)
                || String(format: "%03d", $0.number).contains(query)
            }
        }
        return result
    }

    // MARK: - Cache

    private var lastFetchTime: Date?
    private let cacheInterval: TimeInterval = 300  // 5 minutes

    // MARK: - Public API

    func refresh() async {
        guard !isLoading else { return }

        // Use cache if fresh
        if let lastFetch = lastFetchTime, Date().timeIntervalSince(lastFetch) < cacheInterval, !reflectors.isEmpty {
            return
        }

        isLoading = true
        errorMessage = nil

        do {
            let xlxReflectors = try await fetchXLXDirectory()
            let staticReflectors = generateStaticDirectory()
            reflectors = staticReflectors + xlxReflectors
            lastFetchTime = Date()
        } catch {
            errorMessage = "Failed to load directory: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func forceRefresh() async {
        lastFetchTime = nil
        await refresh()
    }

    // MARK: - XLX API

    private func fetchXLXDirectory() async throws -> [ReflectorInfo] {
        let url = URL(string: "https://xlxapi.rlx.lu/api.php?do=GetXLXDomainMap")!
        let (data, _) = try await URLSession.shared.data(from: url)

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return []
        }

        var results: [ReflectorInfo] = []
        for (key, value) in json {
            guard let info = value as? [String: Any],
                  let numStr = key.replacingOccurrences(of: "XLX", with: "").nilIfEmpty,
                  let number = Int(numStr) else { continue }

            let hostname = (info["Host"] as? String) ?? "xlx\(String(format: "%03d", number)).dstargateway.org"
            let country = (info["Country"] as? String) ?? ""
            let description = (info["Comment"] as? String) ?? ""

            // Generate standard module list (A–Z)
            let modules = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { letter in
                ModuleInfo(letter: letter, connectedCount: 0, lastHeard: nil, lastHeardTime: nil)
            }

            results.append(ReflectorInfo(
                id: "XLX\(String(format: "%03d", number))",
                type: .xlx,
                number: number,
                hostname: hostname,
                modules: modules,
                country: country,
                description: description
            ))
        }

        return results.sorted { $0.number < $1.number }
    }

    // MARK: - Static Directory

    /// Generate a basic static directory for REF, XRF, and DCS reflectors.
    /// These use standard hostname conventions.
    private func generateStaticDirectory() -> [ReflectorInfo] {
        var results: [ReflectorInfo] = []

        let standardModules = Array("ABCDEFGHIJKLMNOPQRSTUVWXYZ").map { letter in
            ModuleInfo(letter: letter, connectedCount: 0, lastHeard: nil, lastHeardTime: nil)
        }

        // Well-known REF reflectors
        let refNumbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 12, 14, 15, 20, 30, 31, 33, 38, 50, 52, 58, 60, 63, 72, 78, 81]
        for num in refNumbers {
            results.append(ReflectorInfo(
                id: "REF\(String(format: "%03d", num))",
                type: .ref,
                number: num,
                hostname: DExtraProtocol.hostname(type: "REF", number: num),
                modules: standardModules,
                country: "",
                description: ""
            ))
        }

        // Well-known DCS reflectors
        let dcsNumbers = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 15, 21, 25, 30, 40, 50, 59]
        for num in dcsNumbers {
            results.append(ReflectorInfo(
                id: "DCS\(String(format: "%03d", num))",
                type: .dcs,
                number: num,
                hostname: DCSProtocol.hostname(number: num),
                modules: standardModules,
                country: "",
                description: ""
            ))
        }

        // Well-known XRF reflectors
        let xrfNumbers = [2, 4, 12, 21, 33, 72, 73, 302, 310, 333, 555, 757]
        for num in xrfNumbers {
            results.append(ReflectorInfo(
                id: "XRF\(String(format: "%03d", num))",
                type: .xrf,
                number: num,
                hostname: DExtraProtocol.hostname(type: "XRF", number: num),
                modules: standardModules,
                country: "",
                description: ""
            ))
        }

        return results.sorted { $0.id < $1.id }
    }
}

// MARK: - Helpers

private extension String {
    var nilIfEmpty: String? {
        isEmpty ? nil : self
    }
}
