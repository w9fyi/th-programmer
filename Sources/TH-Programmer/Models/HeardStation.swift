// HeardStation.swift — Model for stations heard on a D-STAR reflector

import Foundation

/// A station heard transmitting on the connected reflector.
struct HeardStation: Identifiable, Equatable, Sendable {
    let id = UUID()
    let callsign: String
    let timestamp: Date
    var message: String = ""

    /// Formatted timestamp for display (HH:mm:ss).
    var timeString: String {
        let formatter = DateFormatter()
        formatter.dateFormat = "HH:mm:ss"
        return formatter.string(from: timestamp)
    }
}
