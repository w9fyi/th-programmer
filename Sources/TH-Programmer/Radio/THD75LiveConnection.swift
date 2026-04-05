// THD75LiveConnection.swift — Real-time CAT control for TH-D74/D75
//
// The TH-D74/D75 supports live CAT commands over the USB COM port without
// entering clone mode. Commands are ASCII text + \r, same wire format as
// the TS-890S KNS interface. Protocol reverse-engineered from Hamlib thd74.c
// and CHIRP kenwood_live.py.
//
// On connect: send ID\r → verify response, then AI 0\r to suppress auto-info.
// FO command reads/writes the complete VFO state (frequency + mode + tones).

import Foundation

// MARK: - Live Radio State

/// Complete state of one VFO, parsed from or serialised to an FO command.
struct LiveRadioState: Equatable, Sendable {

    var vfo: UInt8 = 0              // 0 = VFO A, 1 = VFO B
    var frequencyHz: Int = 0        // absolute frequency in Hz
    var tuningStep: UInt8 = 0       // step index 0–16
    var toneEnabled: Bool = false   // tone squelch TX
    var ctcssEnabled: Bool = false  // CTCSS tone squelch
    var dcsEnabled: Bool = false    // DCS squelch
    var toneIndex: UInt8 = 0        // index into tone table
    var ctcssIndex: UInt8 = 0       // index into CTCSS table
    var dcsIndex: UInt16 = 0        // DCS code index
    var shift: UInt8 = 0            // 0 = simplex, 1 = +offset, 2 = –offset
    var offsetHz: Int = 0           // repeater offset in Hz
    var mode: UInt8 = 0             // 0=FM 1=DV 2=AM 3=LSB 4=USB 5=CW 6=NFM 7=DR 8=WFM
    var busy: Bool = false          // carrier-detect flag (from BY command, not FO)
    var ptt: Bool = false           // TX state (from TX/RX command, not FO)

    static let modeNames = ["FM", "DV", "AM", "LSB", "USB", "CW", "NFM", "DR", "WFM"]

    /// Frequency formatted as MHz with 4 decimal places, e.g. "146.5200".
    var frequencyMHz: String {
        String(format: "%.4f", Double(frequencyHz) / 1_000_000.0)
    }

    var modeName: String {
        guard Int(mode) < Self.modeNames.count else { return "??" }
        return Self.modeNames[Int(mode)]
    }
}

// MARK: - NMEA Position

/// A parsed GPS position from a $GPRMC sentence.
struct NMEAPosition: Equatable, Sendable {
    var latitude: Double        // decimal degrees, positive = N, negative = S
    var longitude: Double       // decimal degrees, positive = E, negative = W
    var speedKnots: Double      // speed over ground
    var trackDegrees: Double    // course over ground

    /// Formatted as "32.7157° N, 97.0641° W"
    var coordinateString: String {
        let latDir = latitude  >= 0 ? "N" : "S"
        let lonDir = longitude >= 0 ? "E" : "W"
        return String(format: "%.4f° %@, %.4f° %@",
                      abs(latitude), latDir, abs(longitude), lonDir)
    }

    /// Speed formatted for display, e.g. "2.3 kn" or nil when stationary.
    var speedString: String? {
        guard speedKnots >= 0.1 else { return nil }
        return String(format: "%.1f kn", speedKnots)
    }
}

// MARK: - Radio Info State

/// Display-only radio information fetched once on connect (serial, firmware, callsign, clock, GPS).
struct RadioInfoState: Equatable, Sendable {
    var callsign: String = ""           // CS command
    var firmwareVersion: String = ""    // FV command
    var serialNumber: String = ""       // AE command (first field)
    var modelVariant: String = ""       // AE command (second field)
    var clockString: String = ""        // RT command — raw YYMMDDHHMMSS, GPS-synced
    var gpsEnabled: Bool = false        // GP command first field
    var gpsMode: UInt8 = 0              // GP command second field (0=off,1=NMEA,2=internal)
    var gpsFixed: Bool = false          // GS command first field
    var position: NMEAPosition? = nil   // live position from $GPRMC sentences (Menu 981)
}

// MARK: - FO command parser / builder

extension LiveRadioState {

    /// Parse the radio's response to an `FO v\r` query.
    ///
    /// Wire format (comma-separated after "FO "):
    /// `FO v,FFFFFFFFFF,SS,0,T,C,D,TT,CC,DDD,sh,OOOOOOOO,M`
    ///
    /// Fields:
    /// 0  v           – VFO (0=A, 1=B)
    /// 1  FFFFFFFFFF  – frequency Hz, 10 digits zero-padded
    /// 2  SS          – tuning step index, 2 digits
    /// 3  0           – reserved
    /// 4  T           – tone TX enable (0/1)
    /// 5  C           – CTCSS squelch enable (0/1)
    /// 6  D           – DCS squelch enable (0/1)
    /// 7  TT          – tone index, 2 digits
    /// 8  CC          – CTCSS index, 2 digits
    /// 9  DDD         – DCS code index, 3 digits
    /// 10 sh          – shift: 0=simplex 1=+offset 2=–offset
    /// 11 OOOOOOOO    – offset Hz, 8 digits zero-padded
    /// 12 M           – mode digit
    init?(foResponse raw: String) {
        let stripped = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard stripped.hasPrefix("FO ") else { return nil }
        let body = String(stripped.dropFirst(3))
        let parts = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 13 else { return nil }

        vfo          = UInt8(parts[0]) ?? 0
        frequencyHz  = Int(parts[1]) ?? 0
        tuningStep   = UInt8(parts[2]) ?? 0
        // parts[3] is reserved / ignored
        toneEnabled  = parts[4] != "0"
        ctcssEnabled = parts[5] != "0"
        dcsEnabled   = parts[6] != "0"
        toneIndex    = UInt8(parts[7]) ?? 0
        ctcssIndex   = UInt8(parts[8]) ?? 0
        dcsIndex     = UInt16(parts[9]) ?? 0
        shift        = UInt8(parts[10]) ?? 0
        offsetHz     = Int(parts[11]) ?? 0
        mode         = UInt8(parts[12]) ?? 0
    }

    /// Build the FO set-command string (without trailing \r).
    var foCommand: String {
        let freq  = String(format: "%010d", frequencyHz)
        let step  = String(format: "%02d",  tuningStep)
        let tone  = toneEnabled  ? "1" : "0"
        let ctcss = ctcssEnabled ? "1" : "0"
        let dcs   = dcsEnabled   ? "1" : "0"
        let toneI = String(format: "%02d",  toneIndex)
        let ctcsI = String(format: "%02d",  ctcssIndex)
        let dcsI  = String(format: "%03d",  dcsIndex)
        let off   = String(format: "%08d",  offsetHz)
        return "FO \(vfo),\(freq),\(step),0,\(tone),\(ctcss),\(dcs),\(toneI),\(ctcsI),\(dcsI),\(shift),\(off),\(mode)"
    }
}

// MARK: - ME / MN command builder (ChannelMemory → live CAT wire format)

extension ChannelMemory {

    /// Build the ME set-command string (without trailing \r).
    ///
    /// Wire format: `ME NNNN,FFFFFFFFFF,SS,SH,T,C,D,TT,CC,DDD,OOOOOOOO,M,L,UUUUUUUU,RRRRRRRR,SSSSSSSS,DC`
    ///
    /// Fields after channel number:
    ///  1  FFFFFFFFFF – frequency Hz, 10 digits
    ///  2  SS         – tuning step index
    ///  3  SH         – shift: 0=simplex 1=+offset 2=−offset
    ///  4  T          – tone TX enable
    ///  5  C          – CTCSS squelch enable
    ///  6  D          – DCS squelch enable
    ///  7  TT         – rtone index into CTCSS_TONES
    ///  8  CC         – ctone index into CTCSS_TONES
    ///  9  DDD        – DTCS code index, 3 digits
    /// 10  OOOOOOOO   – offset Hz, 8 digits
    /// 11  M          – mode digit
    /// 12  L          – lockout (skip)
    /// 13  UUUUUUUU   – UR call (D-STAR), 8 chars space-padded
    /// 14  RRRRRRRR   – RPT1, 8 chars
    /// 15  SSSSSSSS   – RPT2, 8 chars
    /// 16  DC         – DV code, 2 digits
    var meCommand: String {
        let chStr   = String(format: "%04d", number)
        let freqStr = String(format: "%010d", freq)
        let stepIdx = TUNE_STEPS.firstIndex(of: tuningStep) ?? 0
        let stepStr = String(format: "%02d", stepIdx)
        // split (3) has no ME equivalent — treat as simplex
        let sh      = duplex == .split ? 0 : duplex.rawValue

        var te = 0, ce = 0, de = 0
        switch toneMode {
        case .tone:  te = 1
        case .tsql:  ce = 1
        case .dtcs:  de = 1
        case .cross:
            switch crossMode {
            case .toneToTone:  te = 1; de = 1
            case .dtcsToTone:  de = 1; ce = 1
            case .toneTone:    te = 1; ce = 1
            case .dtcsToDtcs:  de = 1
            }
        case .none:  break
        }

        let rtIdx  = CTCSS_TONES.firstIndex(where: { abs($0 - rtone) < 0.05 }) ?? 0
        let ctIdx  = CTCSS_TONES.firstIndex(where: { abs($0 - ctone) < 0.05 }) ?? 0
        let dtIdx  = DTCS_CODES.firstIndex(of: dtcs) ?? 0
        let ttStr  = String(format: "%02d", rtIdx)
        let ccStr  = String(format: "%02d", ctIdx)
        let dddStr = String(format: "%03d", dtIdx)
        let offStr = String(format: "%08d", offset)
        let lk     = skip ? 1 : 0
        let ur     = mePad(dvURCall,   to: 8)
        let r1     = mePad(dvRPT1Call, to: 8)
        let r2     = mePad(dvRPT2Call, to: 8)
        let dc     = String(format: "%02d", dvCode)

        return "ME \(chStr),\(freqStr),\(stepStr),\(sh),\(te),\(ce),\(de)," +
               "\(ttStr),\(ccStr),\(dddStr),\(offStr),\(mode.rawValue),\(lk)," +
               "\(ur),\(r1),\(r2),\(dc)"
    }

    /// Build the MN set-command string (without trailing \r).
    /// Format: `MN NNNN,NNNNNNNN` — channel + 8-char name, space-padded.
    var mnCommand: String {
        "MN \(String(format: "%04d", number)),\(mePad(name, to: 8))"
    }

    private func mePad(_ s: String, to len: Int) -> String {
        let t = String(s.prefix(len))
        return t + String(repeating: " ", count: Swift.max(0, len - t.count))
    }
}

// MARK: - Connection

/// Manages a live CAT session with the TH-D74/D75.
/// All public methods run synchronously — call from a background thread or via the async wrappers.
final class THD75LiveConnection: @unchecked Sendable {

    private let portPath: String
    private var port: SerialPort

    /// Called on the background I/O thread whenever a $GP* sentence is received
    /// interleaved with CAT responses. RadioStore sets this after connecting.
    var nmeaHandler: ((String) -> Void)?

    init(portPath: String) {
        self.portPath  = portPath
        self.port      = SerialPort(path: portPath)
    }

    /// Whether this is a Bluetooth connection (affects reconnect behavior).
    var isBluetooth: Bool { SerialPort.isBluetoothPort(portPath) }

    /// Non-blocking health check — returns false if the port fd is dead.
    func isHealthy() -> Bool { port.isHealthy() }

    nonisolated deinit { port.close() }

    // MARK: - NMEA-aware line reader

    /// Read one line from the port, forwarding any $GP* sentences to `nmeaHandler`
    /// and retrying until a CAT response (or timeout) arrives.
    private func readCAT(timeout: TimeInterval = 2.0) throws -> String {
        let deadline = Date().addingTimeInterval(timeout)
        while true {
            let remaining = deadline.timeIntervalSinceNow
            guard remaining > 0 else { throw SerialError.timeout(0, 1) }
            let line = try port.readLine(timeout: min(remaining, 2.0))
            if line.hasPrefix("$") {
                nmeaHandler?(line)
                continue
            }
            return line
        }
    }

    // MARK: - Connect / Disconnect

    /// Open the port at 9600 8N1, identify the radio, and disable auto-info.
    func connect() throws {
        try port.open(baudRate: 9600, hardwareFlowControl: false, twoStopBits: false)

        // Bluetooth SPP virtual ports need more warm-up time than USB before
        // the radio accepts CAT commands. Give BT ports 1.5 s, USB 250 ms.
        let isBluetooth = SerialPort.isBluetoothPort(portPath)
        Thread.sleep(forTimeInterval: isBluetooth ? 1.5 : 0.25)

        // Flush any buffered bytes the radio sent during connection setup
        // before sending our first command — otherwise ID\r may be ignored.
        port.flushInput()

        // Identify — retry up to 3 times; BT ports occasionally miss the
        // first command if the data channel isn't fully established yet.
        var idResp = ""
        for attempt in 0..<3 {
            if attempt > 0 { Thread.sleep(forTimeInterval: 1.0) }
            try port.write(Data("ID\r".utf8))
            idResp = (try? readCAT(timeout: 2.0)) ?? ""
            if idResp.contains("TH-D74") || idResp.contains("TH-D75") { break }
        }
        guard idResp.contains("TH-D74") || idResp.contains("TH-D75") else {
            port.close()   // release exclusive lock so diagnostic tests can re-open
            throw LiveError.unexpectedID(idResp)
        }

        // Disable unsolicited auto-info — radio will only respond to queries
        try port.write(Data("AI 0\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    func disconnect() {
        _ = try? port.write(Data("AI 0\r".utf8))
        port.close()
    }

    // MARK: - VFO State

    /// Query the full VFO state via the FO command.
    func getVFOState(vfo: UInt8 = 0) throws -> LiveRadioState {
        try port.write(Data("FO \(vfo)\r".utf8))
        let line = try readCAT(timeout: 2.0)
        guard let state = LiveRadioState(foResponse: line) else {
            throw LiveError.parseError("FO", line)
        }
        return state
    }

    /// Write a new VFO state via the FO command.
    func setVFOState(_ state: LiveRadioState) throws {
        try port.write(Data((state.foCommand + "\r").utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - Frequency / Mode / Shift helpers

    /// Convenience: set only the frequency, preserving the rest of the current state.
    func setFrequency(_ hz: Int, vfo: UInt8 = 0) throws {
        var state = try getVFOState(vfo: vfo)
        state.frequencyHz = hz
        try setVFOState(state)
    }

    /// Set mode on the specified VFO (0=FM 1=DV 2=AM 3=LSB 4=USB 5=CW 6=NFM 7=DR).
    func setMode(_ mode: UInt8, vfo: UInt8 = 0) throws {
        try port.write(Data("MD \(vfo),\(mode)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - VFO selection

    /// Switch which VFO is active (0=A, 1=B).
    func selectVFO(_ vfo: UInt8) throws {
        try port.write(Data("BC \(vfo)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// Query which VFO is currently selected.
    func activeVFO() throws -> UInt8 {
        try port.write(Data("BC\r".utf8))
        let line = try readCAT(timeout: 1.0)
        // Response: "BC v"
        guard line.hasPrefix("BC ") else { return 0 }
        return UInt8(line.dropFirst(3)) ?? 0
    }

    // MARK: - Frequency step

    /// Step the frequency up or down by one tuning step.
    func stepFrequency(up: Bool) throws {
        try port.write(Data((up ? "UP\r" : "DW\r").utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - PTT

    /// Key or unkey the transmitter.
    func ptt(on: Bool) throws {
        try port.write(Data((on ? "TX\r" : "RX\r").utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - Squelch

    /// Set squelch level. Hardware-verified range: 0–5 (decimal).
    func setSquelch(level: UInt8, vfo: UInt8 = 0) throws {
        try port.write(Data("SQ \(vfo),\(min(level, 5))\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    func getSquelch(vfo: UInt8 = 0) throws -> UInt8 {
        try port.write(Data("SQ \(vfo)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        // Response: "SQ v,d" — decimal digit
        return THD75LiveConnection.parseBandValueResponse("SQ", line)?.value ?? 0
    }

    // MARK: - Carrier detect

    /// True when a carrier is present on the specified VFO.
    func getBusy(vfo: UInt8 = 0) throws -> Bool {
        try port.write(Data("BY \(vfo)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        // Response: "BY v,b"
        let parts = line.split(separator: ",")
        return parts.last.flatMap { Int($0) }.map { $0 != 0 } ?? false
    }

    // MARK: - Memory channel write


    /// Write a channel to the radio live via ME + MN commands.
    /// Only writes regular channels (0–999); extended channels are skipped.
    func writeLiveChannel(_ channel: ChannelMemory) throws {
        guard !channel.isExtended else { return }
        try port.write(Data((channel.meCommand + "\r").utf8))
        _ = try? readCAT(timeout: 1.0)
        try port.write(Data((channel.mnCommand + "\r").utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - Radio Settings (AG, BL, BS, PS, VX, CS, DL, LC, VG, VD, SM, RA, SH, SF, VM, MR, TN, PT, MS, GP, GS)

    func getAFGain() throws -> UInt8 {
        try port.write(Data("AG\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseAGResponse(line) ?? 69
    }

    /// Set AF gain. Hardware-verified range: 0–200.
    func setAFGain(_ gain: UInt8) throws {
        try port.write(Data(String(format: "AG %03d\r", min(gain, 200)).utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// BL = Battery level (read-only). 0=empty, 1=low, 2=moderate, 3=full, 4=charging.
    func getBatteryLevel() throws -> UInt8 {
        try port.write(Data("BL\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseBLResponse(line) ?? 0
    }

    /// BS = Bar antenna select. 0=external, 1=internal. Hardware-verified RW.
    func getBarAntenna() throws -> UInt8 {
        try port.write(Data("BS\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseSingleDigitResponse("BS", line) ?? 1
    }

    func setBarAntenna(_ value: UInt8) throws {
        try port.write(Data("BS \(value)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// PS = Power save (read-only via CAT — write returns ?). 0=off, 1=on.
    func getPowerSave() throws -> UInt8 {
        try port.write(Data("PS\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parsePSResponse(line) ?? 0
    }

    func getVOX() throws -> Bool {
        try port.write(Data("VX\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseVXResponse(line) ?? false
    }

    func setVOX(_ on: Bool) throws {
        try port.write(Data("VX \(on ? 1 : 0)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    func getCallsign() throws -> String {
        try port.write(Data("CS\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseCSResponse(line) ?? ""
    }

    func setCallsign(_ call: String) throws {
        let trimmed = String(call.uppercased().prefix(9))
        try port.write(Data("CS \(trimmed)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// DL = Dual/single band mode. 0=dual, 1=single. Hardware-verified RW.
    func getDualBand() throws -> Bool {
        try port.write(Data("DL\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseDLResponse(line) ?? true
    }

    func setDualBand(_ dual: Bool) throws {
        try port.write(Data("DL \(dual ? 0 : 1)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// LC = Backlight control mode. 0=manual, 1=always on, 2=auto, 3=auto DC-in. Hardware-verified RW.
    func getBacklight() throws -> UInt8 {
        try port.write(Data("LC\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseSingleDigitResponse("LC", line) ?? 2
    }

    func setBacklight(_ mode: UInt8) throws {
        try port.write(Data("LC \(mode)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// VG = VOX gain. 0–9. Hardware-verified RW.
    func getVOXGain() throws -> UInt8 {
        try port.write(Data("VG\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseSingleDigitResponse("VG", line) ?? 4
    }

    func setVOXGain(_ gain: UInt8) throws {
        try port.write(Data("VG \(min(gain, 9))\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// VD = VOX delay. 0=250ms, 1=500ms, 2=750ms, 3=1000ms, 4=1500ms, 5=2000ms, 6=3000ms. Hardware-verified RW.
    func getVOXDelay() throws -> UInt8 {
        try port.write(Data("VD\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseSingleDigitResponse("VD", line) ?? 1
    }

    func setVOXDelay(_ delay: UInt8) throws {
        try port.write(Data("VD \(min(delay, 6))\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// SM = S-meter reading (read-only). Returns signal level for the specified band.
    func getSMeter(band: UInt8 = 0) throws -> UInt8 {
        try port.write(Data("SM \(band)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseBandValueResponse("SM", line)?.value ?? 0
    }

    /// RA = Attenuator per band. 0=off, 1=on. Hardware-verified RW.
    func getAttenuator(band: UInt8 = 0) throws -> Bool {
        try port.write(Data("RA \(band)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return (THD75LiveConnection.parseBandValueResponse("RA", line)?.value ?? 0) != 0
    }

    func setAttenuator(band: UInt8, on: Bool) throws {
        try port.write(Data("RA \(band),\(on ? 1 : 0)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// SH = DSP filter width. p1: 0=SSB, 1=CW, 2=AM. p2: width index. Hardware-verified RW.
    func getFilterWidth(mode: UInt8) throws -> UInt8 {
        try port.write(Data("SH \(mode)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseBandValueResponse("SH", line)?.value ?? 0
    }

    func setFilterWidth(mode: UInt8, width: UInt8) throws {
        try port.write(Data("SH \(mode),\(width)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// SF = Tuning step per band. Step index 0–B. Hardware-verified RW.
    func getTuningStep(band: UInt8 = 0) throws -> UInt8 {
        try port.write(Data("SF \(band)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseBandValueResponse("SF", line)?.value ?? 0
    }

    func setTuningStep(band: UInt8, step: UInt8) throws {
        try port.write(Data("SF \(band),\(step)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// VM = VFO/Memory/Call mode per band. 0=VFO, 1=MR, 2=Call, 3=DV. Hardware-verified RW.
    func getVFOMemMode(band: UInt8 = 0) throws -> UInt8 {
        try port.write(Data("VM \(band)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseBandValueResponse("VM", line)?.value ?? 0
    }

    func setVFOMemMode(band: UInt8, mode: UInt8) throws {
        try port.write(Data("VM \(band),\(mode)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// MR = Memory channel recall per band. Returns channel number. Only valid in MR mode.
    func getMemoryChannel(band: UInt8 = 0) throws -> UInt16? {
        try port.write(Data("MR \(band)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        if line == "N" { return nil }  // not in memory mode
        guard line.hasPrefix("MR ") else { return nil }
        return UInt16(line.dropFirst(3).trimmingCharacters(in: .whitespaces))
    }

    func setMemoryChannel(band: UInt8, channel: UInt16) throws {
        try port.write(Data(String(format: "MR %d,%03d\r", band, channel).utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// TN = TNC mode. p1: 0=off, 1=APRS (avoid 2=KISS). p2: band. Hardware-verified RW.
    func getTNCMode() throws -> (mode: UInt8, band: UInt8) {
        try port.write(Data("TN\r".utf8))
        let line = try readCAT(timeout: 1.0)
        guard let r = THD75LiveConnection.parseBandValueResponse("TN", line) else {
            return (0, 0)
        }
        // TN response is "TN mode,band" — first field is mode, second is band
        return (mode: r.band, band: r.value)
    }

    func setTNCMode(mode: UInt8, band: UInt8) throws {
        try port.write(Data("TN \(mode),\(band)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// PT = Beacon mode. 0=manual, 1=PTT, 2=auto, 3=SmartBeaconing. Hardware-verified RW.
    func getBeaconMode() throws -> UInt8 {
        try port.write(Data("PT\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseSingleDigitResponse("PT", line) ?? 0
    }

    func setBeaconMode(_ mode: UInt8) throws {
        try port.write(Data("PT \(mode)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// MS = APRS position source. 0=GPS, 1-5=stored positions. Hardware-verified RW.
    func getPositionSource() throws -> UInt8 {
        try port.write(Data("MS\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseSingleDigitResponse("MS", line) ?? 0
    }

    func setPositionSource(_ source: UInt8) throws {
        try port.write(Data("MS \(source)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// GP = GPS enable + PC output. Hardware-verified RW.
    func setGPS(enabled: Bool, pcOutput: Bool) throws {
        try port.write(Data("GP \(enabled ? 1 : 0),\(pcOutput ? 1 : 0)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    /// GS = GPS NMEA sentence enables (6 toggles). Hardware-verified partial RW.
    func setGPSSentences(_ enables: [Bool]) throws {
        guard enables.count == 6 else { return }
        let vals = enables.map { $0 ? "1" : "0" }.joined(separator: ",")
        try port.write(Data("GS \(vals)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - TX Power (PC command)

    func getTxPower(band: UInt8 = 0) throws -> UInt8 {
        try port.write(Data("PC \(band)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        guard let result = THD75LiveConnection.parsePCResponse(line) else {
            throw LiveError.parseError("PC", line)
        }
        return result.power
    }

    func setTxPower(band: UInt8, level: UInt8) throws {
        try port.write(Data("PC \(band),\(level)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - D-STAR Callsign Slots (DC/DS commands)

    func getDStarSlot(_ slot: UInt8) throws -> String {
        try port.write(Data("DC \(slot)\r".utf8))
        let line = try readCAT(timeout: 1.0)
        guard let result = THD75LiveConnection.parseDCResponse(line) else {
            throw LiveError.parseError("DC", line)
        }
        return result.callsign
    }

    func setDStarSlot(_ slot: UInt8, callsign: String) throws {
        let cs = String(callsign.prefix(8))
        try port.write(Data("DC \(slot),\(cs)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    func getActiveDStarSlot() throws -> UInt8 {
        try port.write(Data("DS\r".utf8))
        let line = try readCAT(timeout: 1.0)
        guard let slot = THD75LiveConnection.parseDSResponse(line) else {
            throw LiveError.parseError("DS", line)
        }
        return slot
    }

    func setActiveDStarSlot(_ slot: UInt8) throws {
        try port.write(Data("DS \(slot)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - APRS Beacon (BE command)

    /// Trigger an APRS beacon. Returns true on success, false if TNC is off.
    func triggerAPRSBeacon() throws -> Bool {
        try port.write(Data("BE\r".utf8))
        let line = try readCAT(timeout: 2.0)
        return THD75LiveConnection.parseBEResponse(line) ?? false
    }

    // MARK: - Bluetooth (BT command)

    func getBluetooth() throws -> Bool {
        try port.write(Data("BT\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseBTResponse(line) ?? false
    }

    func setBluetooth(_ on: Bool) throws {
        try port.write(Data("BT \(on ? 1 : 0)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - TNC Baud Rate (AS command)

    func getTNCBaudRate() throws -> UInt8 {
        try port.write(Data("AS\r".utf8))
        let line = try readCAT(timeout: 1.0)
        return THD75LiveConnection.parseASResponse(line) ?? 0
    }

    func setTNCBaudRate(_ rate: UInt8) throws {
        try port.write(Data("AS \(rate)\r".utf8))
        _ = try? readCAT(timeout: 1.0)
    }

    // MARK: - Radio Info (AE, FV, CS, RT, GP, GS)

    /// Fetch all display-only radio info in one call (serial, firmware, callsign, clock, GPS).
    func getRadioInfo() throws -> RadioInfoState {
        var info = RadioInfoState()

        try port.write(Data("AE\r".utf8))
        if let line = try? readCAT(timeout: 1.0),
           let ae = THD75LiveConnection.parseAEResponse(line) {
            info.serialNumber = ae.serial
            info.modelVariant  = ae.model
        }

        try port.write(Data("FV\r".utf8))
        if let line = try? readCAT(timeout: 1.0) {
            info.firmwareVersion = THD75LiveConnection.parseFVResponse(line) ?? ""
        }

        try port.write(Data("CS\r".utf8))
        if let line = try? readCAT(timeout: 1.0) {
            info.callsign = THD75LiveConnection.parseCSResponse(line) ?? ""
        }

        try port.write(Data("RT\r".utf8))
        if let line = try? readCAT(timeout: 1.0) {
            info.clockString = THD75LiveConnection.parseRTResponse(line) ?? ""
        }

        try port.write(Data("GP\r".utf8))
        if let line = try? readCAT(timeout: 1.0),
           let gp = THD75LiveConnection.parseGPResponse(line) {
            info.gpsEnabled = gp.enabled
            info.gpsMode    = gp.mode
        }

        try port.write(Data("GS\r".utf8))
        if let line = try? readCAT(timeout: 1.0) {
            info.gpsFixed = THD75LiveConnection.parseGSResponse(line) ?? false
        }

        return info
    }

    /// Fetch all live-settable settings in one pass.
    func getLiveSettings() throws -> (afGain: UInt8, backlight: UInt8, barAntenna: UInt8,
                                       powerSave: UInt8, voxOn: Bool, voxGain: UInt8,
                                       voxDelay: UInt8, dualBand: Bool, attA: Bool, attB: Bool) {
        let ag  = (try? getAFGain())       ?? 69
        let lc  = (try? getBacklight())    ?? 2
        let bs  = (try? getBarAntenna())   ?? 1
        let ps  = (try? getPowerSave())    ?? 0
        let vx  = (try? getVOX())          ?? false
        let vg  = (try? getVOXGain())      ?? 4
        let vd  = (try? getVOXDelay())     ?? 1
        let dl  = (try? getDualBand())     ?? true
        let ra0 = (try? getAttenuator(band: 0)) ?? false
        let ra1 = (try? getAttenuator(band: 1)) ?? false
        return (ag, lc, bs, ps, vx, vg, vd, dl, ra0, ra1)
    }
}

// MARK: - Async wrappers

extension THD75LiveConnection {

    static func asyncConnect(portPath: String) async throws -> THD75LiveConnection {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                let conn = THD75LiveConnection(portPath: portPath)
                do {
                    try conn.connect()
                    cont.resume(returning: conn)
                } catch {
                    cont.resume(throwing: error)
                }
            }
        }
    }

    func asyncGetVFOState(vfo: UInt8 = 0) async throws -> LiveRadioState {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.getVFOState(vfo: vfo)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetVFOState(_ state: LiveRadioState) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setVFOState(state); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetFrequency(_ hz: Int, vfo: UInt8 = 0) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setFrequency(hz, vfo: vfo); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncStepFrequency(up: Bool) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.stepFrequency(up: up); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncPTT(on: Bool) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.ptt(on: on); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSelectVFO(_ vfo: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.selectVFO(vfo); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncWriteLiveChannel(_ channel: ChannelMemory) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.writeLiveChannel(channel); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncGetRadioInfo() async throws -> RadioInfoState {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.getRadioInfo()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncGetLiveSettings() async throws -> (afGain: UInt8, backlight: UInt8, barAntenna: UInt8,
                                                   powerSave: UInt8, voxOn: Bool, voxGain: UInt8,
                                                   voxDelay: UInt8, dualBand: Bool, attA: Bool, attB: Bool) {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.getLiveSettings()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetAFGain(_ gain: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setAFGain(gain); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetBacklight(_ mode: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setBacklight(mode); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetBarAntenna(_ value: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setBarAntenna(value); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetVOX(_ on: Bool) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setVOX(on); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetVOXGain(_ gain: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setVOXGain(gain); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetVOXDelay(_ delay: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setVOXDelay(delay); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetDualBand(_ dual: Bool) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setDualBand(dual); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetAttenuator(band: UInt8, on: Bool) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setAttenuator(band: band, on: on); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetFilterWidth(mode: UInt8, width: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setFilterWidth(mode: mode, width: width); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetTuningStep(band: UInt8, step: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setTuningStep(band: band, step: step); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetVFOMemMode(band: UInt8, mode: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setVFOMemMode(band: band, mode: mode); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncGetSMeter(band: UInt8 = 0) async throws -> UInt8 {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.getSMeter(band: band)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetTNCMode(mode: UInt8, band: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setTNCMode(mode: mode, band: band); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetBeaconMode(_ mode: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setBeaconMode(mode); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetPositionSource(_ source: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setPositionSource(source); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetCallsign(_ call: String) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setCallsign(call); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncGetTxPower(band: UInt8 = 0) async throws -> UInt8 {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.getTxPower(band: band)) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetTxPower(band: UInt8, level: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setTxPower(band: band, level: level); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetDStarSlot(_ slot: UInt8, callsign: String) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setDStarSlot(slot, callsign: callsign); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncGetActiveDStarSlot() async throws -> UInt8 {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.getActiveDStarSlot()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetActiveDStarSlot(_ slot: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setActiveDStarSlot(slot); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncTriggerAPRSBeacon() async throws -> Bool {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { cont.resume(returning: try self.triggerAPRSBeacon()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetBluetooth(_ on: Bool) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setBluetooth(on); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }

    func asyncSetTNCBaudRate(_ rate: UInt8) async throws {
        try await withCheckedThrowingContinuation { cont in
            DispatchQueue.global(qos: .userInitiated).async {
                do    { try self.setTNCBaudRate(rate); cont.resume(returning: ()) }
                catch { cont.resume(throwing: error) }
            }
        }
    }
}

// MARK: - Static response parsers (testable without hardware)

extension THD75LiveConnection {

    static func parseAGResponse(_ raw: String) -> UInt8? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("AG ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces))
    }

    /// BL = Battery level. Parse "BL d".
    static func parseBLResponse(_ raw: String) -> UInt8? {
        parseSingleDigitResponse("BL", raw)
    }

    /// BS = Bar antenna. Parse "BS d". 0=external, 1=internal.
    static func parseBSResponse(_ raw: String) -> UInt8? {
        parseSingleDigitResponse("BS", raw)
    }

    static func parsePSResponse(_ raw: String) -> UInt8? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("PS ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces))
    }

    static func parseVXResponse(_ raw: String) -> Bool? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("VX ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces)).map { $0 != 0 }
    }

    static func parseCSResponse(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("CS ") else { return nil }
        let call = String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return call.isEmpty ? nil : call
    }

    static func parseDLResponse(_ raw: String) -> Bool? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("DL ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces)).map { $0 != 0 }
    }

    static func parseFVResponse(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("FV ") else { return nil }
        let v = String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return v.isEmpty ? nil : v
    }

    static func parseAEResponse(_ raw: String) -> (serial: String, model: String)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("AE ") else { return nil }
        let parts = String(s.dropFirst(3)).split(separator: ",", maxSplits: 1).map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2 else { return nil }
        return (serial: parts[0], model: parts[1])
    }

    static func parseRTResponse(_ raw: String) -> String? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("RT ") else { return nil }
        let t = String(s.dropFirst(3)).trimmingCharacters(in: .whitespaces)
        return t.isEmpty ? nil : t
    }

    static func parseGPResponse(_ raw: String) -> (enabled: Bool, mode: UInt8)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("GP ") else { return nil }
        let parts = String(s.dropFirst(3)).split(separator: ",").map {
            $0.trimmingCharacters(in: .whitespaces)
        }
        guard parts.count >= 2,
              let en   = UInt8(parts[0]),
              let mode = UInt8(parts[1]) else { return nil }
        return (enabled: en != 0, mode: mode)
    }

    static func parseGSResponse(_ raw: String) -> Bool? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("GS ") else { return nil }
        let parts = String(s.dropFirst(3)).split(separator: ",")
        guard let first = parts.first,
              let v = UInt8(first.trimmingCharacters(in: .whitespaces)) else { return nil }
        return v != 0
    }

    /// Generic parser for "XX d" responses (single digit/number after prefix).
    static func parseSingleDigitResponse(_ prefix: String, _ raw: String) -> UInt8? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix(prefix + " ") else { return nil }
        return UInt8(s.dropFirst(prefix.count + 1).trimmingCharacters(in: .whitespaces))
    }

    /// Generic parser for "XX band,value" responses (two comma-separated fields).
    static func parseBandValueResponse(_ prefix: String, _ raw: String) -> (band: UInt8, value: UInt8)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix(prefix + " ") else { return nil }
        let parts = String(s.dropFirst(prefix.count + 1)).split(separator: ",")
        guard parts.count >= 2,
              let b = UInt8(parts[0].trimmingCharacters(in: .whitespaces)),
              let v = UInt8(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (band: b, value: v)
    }

    /// Format a raw RT clock string "YYMMDDHHMMSS" as "20YY-MM-DD HH:MM".
    static func formatClockString(_ raw: String) -> String? {
        guard raw.count == 12 else { return nil }
        let chars = Array(raw)
        let yy = String(chars[0..<2])
        let mo = String(chars[2..<4])
        let dd = String(chars[4..<6])
        let hh = String(chars[6..<8])
        let mm = String(chars[8..<10])
        return "20\(yy)-\(mo)-\(dd) \(hh):\(mm)"
    }

    /// Parse a $GPRMC sentence into an NMEAPosition.
    ///
    /// Wire format:
    /// `$GPRMC,HHMMSS.ss,A,DDMM.MMMM,N,DDDMM.MMMM,W,spd,trk,DDMMYY,,*hh`
    ///
    /// Returns nil when the sentence is void (status field = "V") or malformed.
    static func parseNMEAPosition(_ sentence: String) -> NMEAPosition? {
        let s = sentence.trimmingCharacters(in: .whitespacesAndNewlines)
        // Strip optional checksum ("*XX") before splitting
        let body = s.contains("*") ? String(s[s.startIndex..<s.lastIndex(of: "*")!]) : s
        let parts = body.split(separator: ",", omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 9,
              parts[0] == "$GPRMC",
              parts[2] == "A"          // A = active fix, V = void
        else { return nil }

        guard let lat = parseNMEACoord(parts[3], hemi: parts[4]),
              let lon = parseNMEACoord(parts[5], hemi: parts[6])
        else { return nil }

        let speed = Double(parts[7]) ?? 0.0
        let track = Double(parts[8]) ?? 0.0
        return NMEAPosition(latitude: lat, longitude: lon,
                            speedKnots: speed, trackDegrees: track)
    }

    /// Convert an NMEA coordinate string (DDMM.MMMM or DDDMM.MMMM) + hemisphere
    /// letter into a signed decimal-degree value.
    private static func parseNMEACoord(_ value: String, hemi: String) -> Double? {
        guard !value.isEmpty,
              let dotIdx = value.firstIndex(of: "."),
              dotIdx >= value.index(value.startIndex, offsetBy: 2)
        else { return nil }
        // Minutes start 2 characters before the decimal point
        let minStart = value.index(dotIdx, offsetBy: -2)
        guard let degrees = Double(value[value.startIndex..<minStart]),
              let minutes = Double(value[minStart...])
        else { return nil }
        let decimal = degrees + minutes / 60.0
        return (hemi == "S" || hemi == "W") ? -decimal : decimal
    }

    // MARK: - TX Power (PC)

    /// Parse "PC p1,p2" — TX power for a band.
    /// p1 = band (0=A, 1=B), p2 = power (0=High, 1=Medium, 2=Low, 3=EL).
    static func parsePCResponse(_ raw: String) -> (band: UInt8, power: UInt8)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("PC ") else { return nil }
        let parts = String(s.dropFirst(3)).split(separator: ",")
        guard parts.count >= 2,
              let b = UInt8(parts[0].trimmingCharacters(in: .whitespaces)),
              let p = UInt8(parts[1].trimmingCharacters(in: .whitespaces)) else { return nil }
        return (band: b, power: p)
    }

    // MARK: - D-STAR Callsign Slots (DC)

    /// Parse "DC p1,p2[,]" — D-STAR callsign slot.
    /// p1 = slot (1–6), p2 = callsign. Trailing comma is normal.
    static func parseDCResponse(_ raw: String) -> (slot: UInt8, callsign: String)? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("DC ") else { return nil }
        let parts = String(s.dropFirst(3)).split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard parts.count >= 2,
              let slot = UInt8(parts[0].trimmingCharacters(in: .whitespaces)) else { return nil }
        // Strip trailing comma residue and whitespace from callsign
        let callsign = parts[1].trimmingCharacters(in: .whitespaces)
            .trimmingCharacters(in: CharacterSet(charactersIn: ","))
            .trimmingCharacters(in: .whitespaces)
        return (slot: slot, callsign: callsign)
    }

    // MARK: - D-STAR Active Slot (DS)

    /// Parse "DS p1" — active D-STAR slot (1–6).
    static func parseDSResponse(_ raw: String) -> UInt8? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("DS ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces))
    }

    // MARK: - APRS Beacon (BE)

    /// Parse BE response — "BE" = success (true), "N" = TNC off (false).
    static func parseBEResponse(_ raw: String) -> Bool? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        if s == "BE" { return true }
        if s == "N"  { return false }
        return nil
    }

    // MARK: - Bluetooth (BT)

    /// Parse "BT p1" — Bluetooth on/off (0=off, 1=on).
    static func parseBTResponse(_ raw: String) -> Bool? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("BT ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces)).map { $0 != 0 }
    }

    // MARK: - TNC Baud Rate (AS)

    /// Parse "AS p1" — TNC baud rate (0=1200, 1=9600).
    static func parseASResponse(_ raw: String) -> UInt8? {
        let s = raw.trimmingCharacters(in: .whitespacesAndNewlines)
        guard s.hasPrefix("AS ") else { return nil }
        return UInt8(s.dropFirst(3).trimmingCharacters(in: .whitespaces))
    }
}

// MARK: - Errors

enum LiveError: Error, LocalizedError {
    case unexpectedID(String)
    case parseError(String, String)
    case notConnected

    var errorDescription: String? {
        switch self {
        case .unexpectedID(let got):
            return "Unexpected radio ID: \"\(got)\" — expected TH-D74 or TH-D75"
        case .parseError(let cmd, let resp):
            return "Could not parse \(cmd) response: \"\(resp)\""
        case .notConnected:
            return "Live connection is not open"
        }
    }
}
