// THD75Connection.swift — TH-D74/D75 clone protocol state machine
// Ported from CHIRP thd74.py: THD74Radio.download / upload / read_block / write_block

import Foundation

// MARK: - Byte-level debug log

/// Writes a timestamped hex/ASCII log to /tmp/thd75_swift.log.
/// Rotate: each open() call appends a fresh session header.
final class THD75Log {
    static let path = "/tmp/thd75_swift.log"
    private static var t0 = Date()
    private static var handle: FileHandle? = nil

    static func startSession(port: String) {
        t0 = Date()
        let header = "\n\n=== SESSION \(Date()) port=\(port) ===\n"
        if FileManager.default.fileExists(atPath: path) {
            if let fh = FileHandle(forWritingAtPath: path) {
                fh.seekToEndOfFile()
                fh.write(header.data(using: .utf8)!)
                handle = fh
            }
        } else {
            FileManager.default.createFile(atPath: path, contents: header.data(using: .utf8))
            handle = FileHandle(forWritingAtPath: path)
        }
        handle?.seekToEndOfFile()
    }

    static func log(_ direction: String, _ data: Data) {
        let elapsed = String(format: "+%.3fs", Date().timeIntervalSince(t0))
        let hex   = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = String(data.map { ($0 >= 0x20 && $0 < 0x7F) ? Character(UnicodeScalar($0)) : Character(".") })
        let line  = "\(elapsed)  \(direction.padding(toLength: 14, withPad: " ", startingAt: 0))  \(hex.padding(toLength: 48, withPad: " ", startingAt: 0))  |\(ascii)|\n"
        handle?.write(line.data(using: .utf8) ?? Data())
        print(line, terminator: "")   // also visible in Xcode/console
    }

    static func note(_ msg: String) {
        let elapsed = String(format: "+%.3fs", Date().timeIntervalSince(t0))
        let line = "\(elapsed)  NOTE           \(msg)\n"
        handle?.write(line.data(using: .utf8) ?? Data())
        print(line, terminator: "")
    }

    nonisolated deinit {}
}

// MARK: - Progress

struct CloneProgress: Sendable {
    var message: String
    var current: Int
    var total: Int
    var fraction: Double { total > 0 ? Double(current) / Double(total) : 0 }
}

// MARK: - Connection

/// Manages the serial port lifecycle and the clone-mode protocol with the radio.
/// All public methods are safe to call from any thread; progress callbacks are
/// invoked on the calling thread (typically a background DispatchQueue).
final class THD75Connection {

    private let portPath: String
    private var port: SerialPort
    let model: RadioModel

    // Wire protocol: 256-byte payload per block (same for both models).
    private static let protoBlockSize = 256

    init(portPath: String, model: RadioModel = .d74) {
        self.portPath = portPath
        self.model = model
        self.port = SerialPort(path: portPath)
    }

    nonisolated deinit {}

    // MARK: - Open / Close

    /// True when the port is a Bluetooth SPP virtual port.
    /// Bluetooth SPP has no real CTS/RTS signals, so hardware flow control must be off.
    var isBluetooth: Bool { SerialPort.isBluetoothPort(portPath) }

    /// Open the port and enter clone mode.
    /// Uses 9600 8N1 throughout (no stop-bit switch needed).
    /// After the "0M\r" echo is received, flushInput() instantly discards any
    /// trailing bytes so the first R command is sent within the radio's clone-mode
    /// window (~300–500 ms).  readAvailable() must NOT be used here because VTIME=10
    /// causes every read() to block up to 1 s before returning empty.
    func open() throws {
        THD75Log.startSession(port: portPath)
        THD75Log.note("isBluetooth=\(isBluetooth)")

        try port.open(baudRate: 9600, hardwareFlowControl: false, twoStopBits: false)
        THD75Log.note("port opened 9600 8N1 noHFC")

        // Give the USB CDC-ACM driver time to settle.
        Thread.sleep(forTimeInterval: 0.5)

        // ID / TY / FV — ComInfo entries 0–2.  Read until \r, ignore content.
        for cmd in ["ID", "TY", "FV"] {
            let tx = Data((cmd + "\r").utf8)
            try port.write(tx)
            THD75Log.log("TX \(cmd)", tx)
            let rx = (try? port.readAvailable(maxCount: 32, timeout: 1.0)) ?? Data()
            THD75Log.log("RX \(cmd)", rx)
        }

        // Drain any trailing GPS or command bytes before entering clone mode.
        let preDrain = (try? port.readAvailable(maxCount: 64, timeout: 0.2)) ?? Data()
        if !preDrain.isEmpty { THD75Log.log("drain pre-0M", preDrain) }

        // ComInfo entry 3: send "0M PROGRAM\r", wait for echo "0M\r".
        // The echo may arrive interleaved with a GPS NMEA tail; read until "0M" appears.
        let omCmd = Data("0M PROGRAM\r".utf8)
        try port.write(omCmd)
        THD75Log.log("TX 0M", omCmd)
        var omBytes = Data()
        let omDeadline = Date().addingTimeInterval(5.0)
        while Date() < omDeadline {
            let chunk = (try? port.readAvailable(maxCount: 128, timeout: 1.1)) ?? Data()
            omBytes.append(chunk)
            let s = String(bytes: omBytes, encoding: .ascii) ?? ""
            if s.contains("0M") || s.contains("===") { break }
        }
        THD75Log.log("RX 0M", omBytes)

        let omStr = String(bytes: omBytes, encoding: .ascii) ?? ""
        guard omStr.contains("0M") || omStr.contains("===") else {
            let hex = omBytes.map { String(format: "%02X", $0) }.joined(separator: " ")
            THD75Log.note("FAIL: expected 0M or ===, got \(hex.isEmpty ? "(nothing)" : hex)")
            throw CloneError.unexpectedResponse("0M", hex.isEmpty ? "(nothing)" : hex)
        }
        THD75Log.note("clone mode entry: \(omStr.contains("0M") ? "0M echo" : "=== ready")")

        // D74 switches to 57600 after 0M echo (CHIRP thd74.py behavior — unverified by us).
        // D75 stays at 9600 — switching to 57600 crashes it into MCP error mode.
        // (Reference: thd75 lib radio/programming.rs)
        if model.cloneSwitchesBaud {
            try port.setBaudRate(model.cloneBaudRate, hardwareFlowControl: false, twoStopBits: false)
            THD75Log.note("baud switched to \(model.cloneBaudRate)")
            Thread.sleep(forTimeInterval: 0.15)
        }
        THD75Log.note("open() complete — model=\(model)")
    }

    /// Send a text command and read a fixed number of bytes back (no line terminator assumed).
    private func commandFixed(_ cmd: String, count: Int, timeout: TimeInterval) throws -> String {
        try port.write(Data((cmd + "\r").utf8))
        let data = try port.read(count: count, timeout: timeout)
        return String(bytes: data.prefix { $0 != 0x0D && $0 != 0x0A }, encoding: .ascii) ?? ""
    }

    /// Probe: open port, send "ID\r", return raw bytes as hex string (for diagnostics).
    func probe() throws -> String {
        try port.open(baudRate: 9600, hardwareFlowControl: false)
        defer { port.close() }
        Thread.sleep(forTimeInterval: 0.25)
        try port.write(Data([0x0D, 0x0D]))
        Thread.sleep(forTimeInterval: 0.1)
        _ = try? port.readAvailable(maxCount: 32, timeout: 0.5)
        try port.write(Data("ID\r".utf8))
        let data = (try? port.readAvailable(maxCount: 32, timeout: 2.0)) ?? Data()
        if data.isEmpty { return "(no response)" }
        let hex = data.map { String(format: "%02X", $0) }.joined(separator: " ")
        let ascii = String(bytes: data.filter { $0 >= 0x20 && $0 < 0x7F }, encoding: .ascii) ?? ""
        return "hex: \(hex)  ascii: \(ascii)"
    }

    func close() {
        port.close()
    }

    // MARK: - Protocol Diagnostic

    /// Tries every plausible command variant in a single clone session and logs every response.
    /// open() must have been called first. Results are in /tmp/thd75_swift.log.
    /// Press "Run Protocol Diagnostic" in Settings → Communication — do NOT press Download.
    func diagnose() {
        THD75Log.note("=== DIAGNOSE START ===")

        // Loops until the full `secs` duration elapses (VTIME returns after ~1s of silence
        // per read() call; we re-call until deadline so nothing is missed).
        func listen(_ label: String, _ secs: TimeInterval) {
            var allData = Data()
            let deadline = Date().addingTimeInterval(secs)
            while Date() < deadline {
                let rx = (try? port.readAvailable(maxCount: 320, timeout: 1.1)) ?? Data()
                if rx.isEmpty { continue }
                allData.append(rx)
            }
            if allData.isEmpty { THD75Log.note("\(label): silence") }
            else { THD75Log.log(label, allData) }
        }

        func tx(_ label: String, _ bytes: [UInt8]) {
            let d = Data(bytes)
            THD75Log.note("\(label): TX \(d.map { String(format: "%02X", $0) }.joined(separator: " "))")
            try? port.write(d)
        }

        func probe(_ label: String, _ bytes: [UInt8], listenSecs: TimeInterval = 3.0) {
            tx(label, bytes)
            listen("\(label) RX", listenSecs)
        }

        func switchBaud(_ baud: Int32) {
            THD75Log.note("--- baud → \(baud) ---")
            try? port.setBaudRate(baud, hardwareFlowControl: false, twoStopBits: true)
        }

        // ── Phase 1: 1s delay → 0x06 → if 0x15 → passive listen 30s ────────────
        // Key finding: confirmed working session (03:47:40) had 0x06 sent ~1 second
        // AFTER the 0M echo (1s VTIME delay from consuming leftover \r byte).
        // All sessions that sent 0x06 immediately after echo (GPS-active) got silence.
        // This test: deliberate 1s delay, then 0x06, then passive listen (no R).
        THD75Log.note("PHASE1: 1s delay, then 0x06, then passive listen 30s after reply")
        usleep(1_000_000)  // 1 second delay — match timing of confirmed working session
        try? port.write(Data([0x06]))
        THD75Log.note("PHASE1: sent 0x06 (after 1s delay)")
        var p1Reply = Data()
        let p1Dead = Date().addingTimeInterval(2.0)
        while Date() < p1Dead {
            let rx = (try? port.readAvailable(maxCount: 16, timeout: 1.1)) ?? Data()
            if !rx.isEmpty { p1Reply = rx; break }
        }
        if !p1Reply.isEmpty {
            THD75Log.log("PHASE1 reply", p1Reply)
            // KEY TEST: passive listen 30s — does radio PUSH blocks after 0x15?
            // (All previous tests sent R after 0x15; none tried just listening.)
            THD75Log.note("PHASE1: passive listen 30s (no TX, testing push mode)")
            listen("PHASE1 passive after 0x15", 30.0)
            // If radio pushed nothing, try R as fallback
            tx("PHASE1 R blk=0 (fallback)", [0x52, 0x00, 0x00, 0x01, 0x00])
            listen("PHASE1 R RX", 5.0)
        } else {
            THD75Log.note("PHASE1: no reply — trying 0x06 immediately (GPS-void path)")
            try? port.write(Data([0x06]))
            THD75Log.note("PHASE1b: sent 0x06 immediately")
            var p1bReply = Data()
            let p1bDead = Date().addingTimeInterval(2.0)
            while Date() < p1bDead {
                let rx = (try? port.readAvailable(maxCount: 16, timeout: 1.1)) ?? Data()
                if !rx.isEmpty { p1bReply = rx; break }
            }
            if !p1bReply.isEmpty {
                THD75Log.log("PHASE1b reply", p1bReply)
                THD75Log.note("PHASE1b: passive listen 30s")
                listen("PHASE1b passive after 0x15", 30.0)
                tx("PHASE1b R blk=0 (fallback)", [0x52, 0x00, 0x00, 0x01, 0x00])
                listen("PHASE1b R RX", 5.0)
            } else {
                THD75Log.note("PHASE1b: no reply either — radio timed out or state mismatch")
            }
        }

        // ── Phase 2: baud rate sweep — switch then send R immediately ────────────
        // Hypothesis: radio switches baud after the 0M echo; our 9600-baud R is invisible.
        for baud in [115200, 57600, 38400, 19200] as [Int32] {
            switchBaud(baud)
            probe("BAUD\(baud) R", [0x52, 0x00, 0x00, 0x01, 0x00], listenSecs: 5.0)
        }

        // ── Phase 3: back to 9600, passive listen (radio pushes without request?) ─
        switchBaud(9600)
        THD75Log.note("PHASE3: 9600 passive listen 5s")
        listen("PHASE3 passive", 5.0)

        // ── Phase 4: 115200 passive listen ───────────────────────────────────────
        switchBaud(115200)
        THD75Log.note("PHASE4: 115200 passive listen 5s")
        listen("PHASE4 passive", 5.0)

        // ── Phase 5: 9600 fallback variants ──────────────────────────────────────
        switchBaud(9600)
        probe("P5 0x15",          [0x15])
        probe("P5 0x06",          [0x06])
        probe("P5 R len=0",       [0x52, 0x00, 0x00, 0x00, 0x00])
        probe("P5 r",             [0x72, 0x00, 0x00, 0x01, 0x00])
        probe("P5 R+chk",         [0x52, 0x00, 0x00, 0x01, 0x00, 0x53])
        probe("P5 0x02 STX",      [0x02])
        probe("P5 D\\r",          [0x44, 0x0D])

        THD75Log.note("=== DIAGNOSE END ===")
    }

    // MARK: - Download

    /// Download the full memory image from the radio.
    /// Calls `progress` periodically. Runs synchronously — call from a background thread.
    ///
    /// Protocol (CHIRP thd74.py — confirmed for TH-D74/D75):
    ///   1. open() has already sent 0M PROGRAM, received the 0M echo, and switched to 57600 baud.
    ///   2. Radio sends one "ready" byte at 57600 — discard it (CHIRP does pipe.read(1)).
    ///   3. For each block: send R + block_num (BE uint16) + 0x0000,
    ///      receive W + block_num + 0x0000 + protoBlockSize bytes,
    ///      send 0x06 ACK, receive 0x06 ACK.
    ///   4. Send 'E' when done.
    ///   No handshake byte is sent before block I/O.
    func download(progress: ((CloneProgress) -> Void)? = nil) throws -> MemoryMap {
        // ── Ready byte ───────────────────────────────────────────────────────
        // After SET_LINE_CODING the radio sends one byte to signal it is ready
        // for R commands. CHIRP discards it without checking. We use
        // readAvailable() so we don't block if the byte was already consumed or
        // if the radio sends more than one byte here.
        let readyBytes = (try? port.readAvailable(maxCount: 16, timeout: 0.5)) ?? Data()
        if readyBytes.isEmpty {
            THD75Log.note("ready bytes: none received (proceeding anyway)")
        } else {
            THD75Log.log("ready bytes (discarded)", readyBytes)
        }

        // ── Block loop ───────────────────────────────────────────────────────
        let expectedSize = model.cloneImageSize
        var raw = Data(capacity: expectedSize)
        let total = model.cloneBlocks

        for block in 0..<total {
            let blockData = try readBlock(block)
            raw.append(contentsOf: blockData)
            progress?(CloneProgress(message: "Reading from radio", current: block + 1, total: total))
        }

        try port.write(Data([UInt8(ascii: "E")]))
        THD75Log.note("download complete: \(raw.count) bytes in \(total) blocks")

        // Pad or trim to exactly expectedSize so MemoryMap gets a consistent buffer.
        if raw.count < expectedSize {
            THD75Log.note("WARNING: image short by \(expectedSize - raw.count) bytes — padding with 0xFF")
            raw.append(contentsOf: Array(repeating: UInt8(0xFF), count: expectedSize - raw.count))
        } else if raw.count > expectedSize {
            THD75Log.note("WARNING: image long by \(raw.count - expectedSize) bytes — trimming")
            raw = raw.prefix(expectedSize)
        }
        return MemoryMap(data: raw)
    }

    // MARK: - Upload

    /// Upload a memory image to the radio.
    /// Calls `progress` periodically. Runs synchronously — call from a background thread.
    func upload(_ map: MemoryMap, progress: ((CloneProgress) -> Void)? = nil) throws {
        let total = model.cloneBlocks

        for block in 0..<total {
            try writeBlock(block, map: map.raw)
            progress?(CloneProgress(message: "Writing to radio", current: block + 1, total: total))
        }

        try port.write(Data([UInt8(ascii: "E")]))
    }

    // MARK: - Block Read

    /// Read one block from the radio using the R-command protocol (CHIRP thd74.py).
    ///
    /// Exchange:
    ///   TX: [0x52, block>>8, block&0xFF, 0x00, 0x00]          (R command, 5 bytes)
    ///   RX: [0x57, block>>8, block&0xFF, 0x00, 0x00]          (W header, 5 bytes)
    ///       + protoBlockSize bytes of payload
    ///   TX: [0x06]                                             (ACK)
    ///   RX: [0x06]                                             (radio ACK)
    private func readBlock(_ block: Int) throws -> Data {
        let verbose = block < 5 || block % 256 == 0

        // Send R command.
        let rCmd = Data([0x52, UInt8((block >> 8) & 0xFF), UInt8(block & 0xFF), 0x00, 0x00])
        try port.write(rCmd)
        if verbose { THD75Log.log("TX R[\(block)]", rCmd) }

        // Receive W header (5 bytes).
        let header = try port.read(count: 5, timeout: 5.0)
        guard header[0] == 0x57 else {
            THD75Log.log("bad header block \(block)", header)
            throw CloneError.unexpectedBlockResponse(block, header)
        }
        let blockNum = (Int(header[1]) << 8) | Int(header[2])
        if verbose { THD75Log.log("RX hdr[\(block)] blk=\(blockNum)", header) }
        if blockNum != block {
            THD75Log.note("block mismatch: expected \(block) got \(blockNum)")
            throw CloneError.blockMismatch(expected: block, got: blockNum)
        }

        // Receive payload.
        let payload = try port.read(count: Self.protoBlockSize, timeout: 3.0)
        if verbose { THD75Log.log("RX data[\(block)]", payload.prefix(16)) }

        // Send ACK, expect ACK back.
        try port.write(Data([0x06]))
        if verbose { THD75Log.note("TX 0x06 ACK block \(block)") }

        let ack = try port.read(count: 1, timeout: 2.0)
        if ack[0] != 0x06 {
            THD75Log.log("bad ACK block \(block)", ack)
            // Non-fatal on early blocks — log and continue.
            if block < 3 { throw CloneError.noACK(block) }
        }
        if verbose { THD75Log.note("block \(block) OK") }

        return payload
    }

    // MARK: - Block Write

    /// Write one block to the radio.
    /// Java: W command = [0x57, block>>8, block&0xFF, 0x00, 0x00] + protoBlockSize bytes data.
    private func writeBlock(_ block: Int, map: Data) throws {
        let verbose = block < 5 || block % 256 == 0
        let base = block * Self.protoBlockSize
        let slice = map.subdata(in: base..<min(base + Self.protoBlockSize, map.count))
        guard slice.count == Self.protoBlockSize else {
            throw CloneError.shortBlock(block, slice.count)
        }

        // Header: 'W' + block as BE uint16 + 0x00 0x00
        var packet = Data([0x57, UInt8((block >> 8) & 0xFF), UInt8(block & 0xFF), 0x00, 0x00])
        packet.append(contentsOf: slice)
        if verbose { THD75Log.log("TX W[\(block)]", packet.prefix(21)) }  // header + first 16 bytes
        try port.write(packet)

        // Receive ACK (retry up to 10 times)
        var ack: UInt8 = 0
        for _ in 0..<10 {
            let b = try? port.read(count: 1, timeout: 2.0)
            ack = b?[0] ?? 0
            if ack == 0x06 { break }
        }
        if ack != 0x06 {
            THD75Log.note("bad ACK block \(block): \(String(format: "%02X", ack))")
            throw CloneError.noACK(block)
        }
        if verbose { THD75Log.note("write block \(block) OK") }
    }

    // MARK: - Helpers

    /// Send a text command and read back the response up to '\r', with timeout.
    private func command(_ cmd: String, timeout: TimeInterval = 1.0) throws -> String {
        let cmdData = Data((cmd + "\r").utf8)
        try port.write(cmdData)
        return try port.readLine(timeout: timeout)
    }
}

// MARK: - Async wrapper for SwiftUI

extension THD75Connection {

    /// Probe the port and return a diagnostic hex dump of the ID response.
    static func asyncProbe(portPath: String) async throws -> String {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let conn = THD75Connection(portPath: portPath)
                do {
                    let result = try conn.probe()
                    cont.resume(returning: result)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Open + diagnose on a background thread. Results written to /tmp/thd75_swift.log.
    static func asyncDiagnose(
        portPath: String,
        model: RadioModel = .d74
    ) async throws {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let conn = THD75Connection(portPath: portPath, model: model)
                do {
                    try conn.open()
                    conn.diagnose()
                    conn.close()
                    cont.resume(returning: ())
                } catch {
                    conn.close()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Open + download on a background thread. Progress sent via `AsyncStream`.
    static func asyncDownload(
        portPath: String,
        model: RadioModel = .d74,
        onProgress: @escaping @Sendable (CloneProgress) -> Void
    ) async throws -> MemoryMap {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let conn = THD75Connection(portPath: portPath, model: model)
                do {
                    try conn.open()
                    let map = try conn.download(progress: onProgress)
                    conn.close()
                    cont.resume(returning: map)
                } catch {
                    conn.close()
                    cont.resume(throwing: error)
                }
            }
        }
    }

    /// Open + upload on a background thread.
    static func asyncUpload(
        portPath: String,
        model: RadioModel = .d74,
        map: MemoryMap,
        onProgress: @escaping @Sendable (CloneProgress) -> Void
    ) async throws {
        return try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let conn = THD75Connection(portPath: portPath, model: model)
                do {
                    try conn.open()
                    try conn.upload(map, progress: onProgress)
                    conn.close()
                    cont.resume(returning: ())
                } catch {
                    conn.close()
                    cont.resume(throwing: error)
                }
            }
        }
    }
}

// MARK: - Errors

enum CloneError: Error, LocalizedError {
    case unexpectedResponse(String, String)
    case unexpectedBlockResponse(Int, Data)
    case blockMismatch(expected: Int, got: Int)
    case noACK(Int)
    case shortBlock(Int, Int)
    case imageSizeMismatch(Int, Int)

    var errorDescription: String? {
        switch self {
        case .unexpectedResponse(let want, let got):
            return "Expected response \"\(want)\", got \"\(got)\""
        case .unexpectedBlockResponse(let block, _):
            return "Invalid response header for block \(block)"
        case .blockMismatch(let expected, let got):
            return "Block number mismatch: expected \(expected), got \(got)"
        case .noACK(let block):
            return "No ACK for block \(block)"
        case .shortBlock(let block, let count):
            return "Block \(block) has only \(count) bytes (expected 256)"
        case .imageSizeMismatch(let got, let want):
            return "Image size mismatch: got \(got) bytes, expected \(want)"
        }
    }
}
