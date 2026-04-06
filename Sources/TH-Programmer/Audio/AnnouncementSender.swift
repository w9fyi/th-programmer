// AnnouncementSender.swift — Sends pre-recorded AMBE announcements to the
// radio via MMDVM protocol (D-STAR header + voice frames + EOT).

import Foundation

/// Sends an array of AMBE frames to the radio as a D-STAR voice transmission
/// via the MMDVM serial transport.
final class AnnouncementSender: @unchecked Sendable {

    /// Filler slow data bytes (same as DExtraProtocol/ircDDBGateway).
    static let fillerSlowData = Data([0x16, 0x29, 0xF5])

    /// 20ms frame pacing in nanoseconds.
    static let framePacingNanos: UInt64 = 20_000_000

    /// D-STAR superframe length.
    static let framesPerSuperframe: UInt8 = 21

    private let transport: any MMDVMTransport
    private let queue: DispatchQueue

    /// Callsign to use in the D-STAR header MY field.
    var myCallsign: String = "AI5OS"

    init(transport: any MMDVMTransport, queue: DispatchQueue) {
        self.transport = transport
        self.queue = queue
    }

    /// Send an announcement (array of 9-byte AMBE frames) to the radio.
    /// Must be called on the bridge queue. Blocks the queue for the
    /// duration of the announcement (frame count * 20ms).
    ///
    /// - Parameter frames: Array of 9-byte AMBE Data frames
    /// - Parameter callsign: Callsign to put in the MY field of the header
    func sendAnnouncement(frames: [Data], callsign: String? = nil) {
        guard !frames.isEmpty else { return }

        let call = callsign ?? myCallsign

        // 1. Send D-STAR header
        let header = MMDVMProtocol.buildDStarHeader(
            myCallsign: call,
            yourCallsign: "CQCQCQ  ",
            rpt1Callsign: "DIRECT  ",
            rpt2Callsign: "        "
        )
        do {
            try transport.send(header)
        } catch {
            return
        }

        // Brief settling delay after header
        Thread.sleep(forTimeInterval: 0.020)

        // 2. Send each AMBE frame paced at 20ms intervals
        var frameCounter: UInt8 = 0
        var targetTime = DispatchTime.now().uptimeNanoseconds

        for (i, ambeFrame) in frames.enumerated() {
            // Pace: wait until target time
            let now = DispatchTime.now().uptimeNanoseconds
            if now < targetTime {
                Thread.sleep(forTimeInterval: Double(targetTime - now) / 1_000_000_000.0)
            }

            // Mark the last frame with end-of-stream bit
            let isLast = (i == frames.count - 1)
            let counter = isLast ? (frameCounter | 0x40) : frameCounter

            let mmdvmFrame = MMDVMProtocol.buildDStarData(
                ambe: ambeFrame,
                slowData: Self.fillerSlowData
            )

            // Patch the frame counter into a custom data frame isn't needed —
            // the radio doesn't inspect the counter for local playback.
            // MMDVMProtocol.buildDStarData already produces the correct
            // [0xE0, length, 0x11, ambe(9), slowdata(3)] format.
            do {
                try transport.send(mmdvmFrame)
            } catch {
                return
            }

            frameCounter = (frameCounter + 1) % Self.framesPerSuperframe
            targetTime += Self.framePacingNanos
        }

        // 3. Send EOT
        let eot = MMDVMProtocol.buildDStarEOT()
        do {
            try transport.send(eot)
        } catch {
            // Best effort
        }
    }
}
