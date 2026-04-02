// SerialPortDiscovery.swift — Smart serial port enumeration for MMDVM devices

import Foundation

/// Transport kind for a serial port.
enum SerialTransportKind: String, CaseIterable, Codable, Identifiable, Sendable {
    case bluetoothSPP
    case usbCDC
    case unknown

    var id: String { rawValue }

    var label: String {
        switch self {
        case .bluetoothSPP: return "Bluetooth SPP"
        case .usbCDC: return "USB CDC"
        case .unknown: return "Unknown"
        }
    }
}

/// A discovered serial port with scoring metadata.
struct RadioSerialPort: Identifiable, Codable, Equatable, Hashable, Sendable {
    let path: String
    let displayName: String
    let transportKind: SerialTransportKind
    let score: Int

    var id: String { path }
}

/// Discovers serial ports and scores them by likelihood of being a TH-D75 in MMDVM mode.
///
/// Scoring:
///   - TH-D75 in name: +200
///   - Kenwood in name: +100
///   - cu.* prefix: +80
///   - Bluetooth SPP: +40
///   - USB CDC: +30
///   - "incoming-port": -200 (macOS Bluetooth incoming port, not useful)
enum SerialPortDiscovery {

    static func discover(
        fileManager: FileManager = .default,
        deviceRoot: String = "/dev"
    ) -> [RadioSerialPort] {
        guard let entries = try? fileManager.contentsOfDirectory(atPath: deviceRoot) else {
            return []
        }
        return ports(from: entries, deviceRoot: deviceRoot)
    }

    static func ports(from entries: [String], deviceRoot: String = "/dev") -> [RadioSerialPort] {
        entries.compactMap { makePort(from: $0, deviceRoot: deviceRoot) }
            .sorted { lhs, rhs in
                if lhs.score == rhs.score {
                    return lhs.displayName < rhs.displayName
                }
                return lhs.score > rhs.score
            }
    }

    private static func makePort(from entry: String, deviceRoot: String) -> RadioSerialPort? {
        guard entry.hasPrefix("cu.") || entry.hasPrefix("tty.") else {
            return nil
        }

        let lowercased = entry.lowercased()
        let kind: SerialTransportKind
        if lowercased.contains("bluetooth") || lowercased.contains("rfcomm") {
            kind = .bluetoothSPP
        } else if lowercased.contains("usbmodem") || lowercased.contains("usbserial") {
            kind = .usbCDC
        } else {
            kind = .unknown
        }

        var score = 0
        if lowercased.hasPrefix("cu.") {
            score += 80
        }
        if lowercased.contains("th-d75") || lowercased.contains("thd75") {
            score += 200
        }
        if lowercased.contains("kenwood") {
            score += 100
        }
        if kind == .bluetoothSPP {
            score += 40
        }
        if kind == .usbCDC {
            score += 30
        }
        if lowercased.contains("incoming-port") {
            score -= 200
        }

        return RadioSerialPort(
            path: "\(deviceRoot)/\(entry)",
            displayName: entry,
            transportKind: kind,
            score: score
        )
    }
}
