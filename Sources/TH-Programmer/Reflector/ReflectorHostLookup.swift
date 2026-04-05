// ReflectorHostLookup.swift — Downloads and caches official D-STAR reflector host files

import Foundation

/// Downloads official host files from g4klx/ircDDBGateway and resolves reflector hostnames.
///
/// Host files map reflector names (e.g., "REF001", "DCS001") to IP addresses or hostnames.
/// Three files are used:
///   - DPlus_Hosts.txt  → REF reflectors (DPlus protocol, but many now run XLX/DExtra)
///   - DExtra_Hosts.txt → XRF reflectors (DExtra protocol)
///   - DCS_Hosts.txt    → DCS reflectors (DCS protocol)
///
/// Format per line: `REFLECTORNAME\tHOSTNAME_OR_IP`
/// Some reflectors have two entries (IP + hostname) — we prefer IP addresses.
final class ReflectorHostLookup: @unchecked Sendable {

    nonisolated deinit {}

    static let shared = ReflectorHostLookup()

    /// Resolved host entry — an IP or hostname for a reflector.
    struct HostEntry: Sendable {
        let reflector: String   // e.g., "REF001"
        let host: String        // IP address or hostname
    }

    // MARK: - State

    private var hosts: [String: String] = [:]  // "REF001" → "1.2.3.4" or "hostname"
    private var lastFetched: Date?
    private let cacheInterval: TimeInterval = 24 * 3600  // 24 hours
    private let queue = DispatchQueue(label: "com.th-programmer.hostlookup")
    private var isFetching = false

    /// Callback fired when host data is loaded/refreshed.
    var onHostsLoaded: (() -> Void)?

    // MARK: - URLs

    // Pi-Star host files are more up-to-date than g4klx — many XRF reflectors
    // have moved IPs and only Pi-Star tracks the current addresses.
    private static let baseURL = "https://www.pistar.uk/downloads/"
    private static let hostFiles = [
        "DPlus_Hosts.txt",
        "DExtra_Hosts.txt",
        "DCS_Hosts.txt"
    ]

    // MARK: - Lookup

    /// Look up the host (IP or hostname) for a reflector.
    /// Returns nil if the reflector is not in the host table.
    func lookup(reflector: String) -> String? {
        queue.sync { hosts[reflector.uppercased()] }
    }

    /// Look up host for a reflector target.
    func lookup(target: ReflectorTarget) -> String? {
        let name = "\(target.type.rawValue)\(String(format: "%03d", target.number))"
        return lookup(reflector: name)
    }

    /// Whether hosts have been loaded.
    var isLoaded: Bool {
        queue.sync { !hosts.isEmpty }
    }

    /// Number of hosts loaded.
    var hostCount: Int {
        queue.sync { hosts.count }
    }

    // MARK: - DPlus Auth

    /// Authenticate with the DPlus trust server to get REF reflector IPs.
    /// These IPs are not available in static host files — only the auth server has them.
    func authenticateDPlus(callsign: String, diagnostic: ((String) -> Void)? = nil, completion: ((Int) -> Void)? = nil) {
        let auth = DPlusAuthenticator(callsign: callsign)
        auth.onDiagnostic = diagnostic
        auth.authenticate { [weak self] result in
            guard let self, let result else {
                completion?(0)
                return
            }
            self.queue.async {
                var count = 0
                for (name, ip) in result.reflectors {
                    self.hosts[name] = ip
                    count += 1
                }
                if count > 0 {
                    self.saveToDisk(self.hosts)
                }
                // Dispatch completion OFF the hostlookup queue — callers may call
                // lookup() which does queue.sync, deadlocking if still on this queue.
                DispatchQueue.main.async {
                    completion?(count)
                }
            }
        }
    }

    // MARK: - Fetch

    /// Fetch host files if not cached or cache expired.
    func ensureLoaded(completion: (() -> Void)? = nil) {
        queue.async { [self] in
            if let lastFetched, Date().timeIntervalSince(lastFetched) < cacheInterval, !hosts.isEmpty {
                DispatchQueue.main.async { completion?() }
                return
            }
            if isFetching {
                DispatchQueue.main.async { completion?() }
                return
            }
            isFetching = true
            fetchAll { [weak self] in
                self?.queue.async {
                    self?.isFetching = false
                    DispatchQueue.main.async { completion?() }
                }
            }
        }
    }

    /// Force refresh from network.
    func refresh(completion: (() -> Void)? = nil) {
        queue.async { [self] in
            guard !isFetching else {
                DispatchQueue.main.async { completion?() }
                return
            }
            isFetching = true
            fetchAll { [weak self] in
                self?.queue.async {
                    self?.isFetching = false
                    DispatchQueue.main.async { completion?() }
                }
            }
        }
    }

    private func fetchAll(completion: @escaping () -> Void) {
        let group = DispatchGroup()
        var allParsed: [(String, String)] = []
        let lock = NSLock()

        // Fetch g4klx host files (REF, DExtra, DCS)
        for file in Self.hostFiles {
            group.enter()
            guard let url = URL(string: Self.baseURL + file) else {
                group.leave()
                continue
            }

            // Pi-Star blocks requests without a proper User-Agent header (403 Forbidden)
            var request = URLRequest(url: url)
            request.setValue("TH-Programmer/1.0", forHTTPHeaderField: "User-Agent")
            let task = URLSession.shared.dataTask(with: request) { data, _, error in
                defer { group.leave() }
                guard let data, error == nil,
                      let text = String(data: data, encoding: .utf8) else { return }

                let parsed = Self.parseHostFile(text)
                lock.lock()
                allParsed.append(contentsOf: parsed)
                lock.unlock()
            }
            task.resume()
        }

        // Fetch XLX reflector list from the official XLX API
        group.enter()
        if let xlxURL = URL(string: "http://xlxapi.rlx.lu/api.php?do=GetReflectorList") {
            let task = URLSession.shared.dataTask(with: xlxURL) { data, _, error in
                defer { group.leave() }
                guard let data, error == nil,
                      let text = String(data: data, encoding: .utf8) else { return }

                let parsed = Self.parseXLXList(text)
                lock.lock()
                allParsed.append(contentsOf: parsed)
                lock.unlock()
            }
            task.resume()
        } else {
            group.leave()
        }

        group.notify(queue: queue) { [weak self] in
            guard let self else { return }
            // Build lookup table — prefer IP addresses over hostnames
            var newHosts: [String: String] = [:]
            for (name, host) in allParsed {
                let key = name.uppercased()
                if let existing = newHosts[key] {
                    // Prefer IP address over hostname
                    if Self.isIPAddress(host) && !Self.isIPAddress(existing) {
                        newHosts[key] = host
                    }
                } else {
                    newHosts[key] = host
                }
            }

            if !newHosts.isEmpty {
                self.hosts = newHosts
                self.lastFetched = Date()
            }

            // Also persist to disk cache
            self.saveToDisk(newHosts)

            DispatchQueue.main.async {
                self.onHostsLoaded?()
            }
            completion()
        }
    }

    // MARK: - Parse

    /// Parse a host file into (name, host) pairs.
    /// Format: "REF001\t192.168.1.1" or "REF001\tref001.example.org"
    /// Lines starting with # are comments.
    static func parseHostFile(_ text: String) -> [(String, String)] {
        var results: [(String, String)] = []
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            guard !trimmed.isEmpty, !trimmed.hasPrefix("#") else { continue }

            let parts = trimmed.components(separatedBy: "\t")
            guard parts.count >= 2 else { continue }

            let name = parts[0].trimmingCharacters(in: .whitespaces).uppercased()
            let host = parts[1].trimmingCharacters(in: .whitespaces)

            guard !name.isEmpty, !host.isEmpty else { continue }
            // Validate name looks like a reflector (3 letter prefix + digits)
            guard name.count >= 4 else { continue }

            results.append((name, host))
        }
        return results
    }

    /// Parse the XLX API XML response into (name, IP) pairs.
    /// The XML is sometimes malformed, so we use regex instead of a proper XML parser.
    static func parseXLXList(_ text: String) -> [(String, String)] {
        var results: [(String, String)] = []
        let namePattern = try? NSRegularExpression(pattern: "<name>(XLX\\d+)</name>")
        let ipPattern = try? NSRegularExpression(pattern: "<lastip>([\\d.]+)</lastip>")

        var currentName: String?
        for line in text.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            let nsLine = trimmed as NSString
            let range = NSRange(location: 0, length: nsLine.length)

            if let match = namePattern?.firstMatch(in: trimmed, range: range),
               match.numberOfRanges >= 2 {
                currentName = nsLine.substring(with: match.range(at: 1))
            }

            if let name = currentName,
               let match = ipPattern?.firstMatch(in: trimmed, range: range),
               match.numberOfRanges >= 2 {
                let ip = nsLine.substring(with: match.range(at: 1))
                if !ip.isEmpty {
                    results.append((name, ip))
                    currentName = nil
                }
            }
        }
        return results
    }

    /// Check if a string looks like an IP address (v4 or v6).
    static func isIPAddress(_ string: String) -> Bool {
        // Simple v4 check: digits and dots
        let v4 = string.allSatisfy { $0.isNumber || $0 == "." }
        if v4 && string.contains(".") { return true }
        // v6: contains colons
        if string.contains(":") { return true }
        return false
    }

    // MARK: - Disk Cache

    private static var cacheURL: URL {
        let cacheDir = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first!
        return cacheDir.appendingPathComponent("com.th-programmer.reflector-hosts.json")
    }

    private func saveToDisk(_ hosts: [String: String]) {
        guard let data = try? JSONEncoder().encode(hosts) else { return }
        try? data.write(to: Self.cacheURL)
    }

    /// Load cached hosts from disk (used on first launch before network fetch).
    func loadFromDisk() {
        queue.async { [self] in
            guard hosts.isEmpty else { return }
            guard let data = try? Data(contentsOf: Self.cacheURL),
                  let cached = try? JSONDecoder().decode([String: String].self, from: data) else { return }
            hosts = cached
            DispatchQueue.main.async {
                self.onHostsLoaded?()
            }
        }
    }

    // MARK: - Fallback Hostname Generation

    /// Generate a fallback hostname when the host file doesn't have an entry.
    /// Uses known conventions per reflector type.
    static func fallbackHostname(type: ReflectorTarget.ReflectorType, number: Int) -> String {
        let num = String(format: "%03d", Swift.max(1, Swift.min(999, number)))
        switch type {
        case .ref:
            return "ref\(num).dstargateway.org"
        case .xrf:
            return "xrf\(num).dstargateway.org"
        case .dcs:
            return "dcs\(num).xreflector.net"
        case .xlx:
            return "xlx\(num).dstargateway.org"
        }
    }
}
