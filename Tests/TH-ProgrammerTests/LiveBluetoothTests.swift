// LiveBluetoothTests.swift — Hardware-in-the-loop CAT tests over Bluetooth SPP
//
// These tests require a TH-D74 or TH-D75 to be:
//   • Paired with this Mac
//   • Powered on with Bluetooth enabled
//   • Menu 985 set to "PC" (so CAT commands work over Bluetooth)
//   • Not already connected to another app (the port must be free)
//
// All tests call XCTSkipUnless when the radio port is absent, so the normal
// test suite continues to pass green without hardware attached.
//
// The connection is established ONCE for the entire class to avoid repeated
// Bluetooth link setup overhead on each setUp.

import XCTest
@testable import TH_Programmer

final class LiveBluetoothTests: XCTestCase {

    nonisolated deinit {}

    // Shared connection — opened once for the whole class.
    private static var sharedConnection: THD75LiveConnection?
    private static var skipReason: String?

    // MARK: - Class-level fixture (runs once before all tests)

    override class func setUp() {
        super.setUp()
        guard let port = findRadioPort() else {
            skipReason = "No TH-D74/D75 Bluetooth port found in /dev — radio may be off or not paired"
            return
        }
        let conn = THD75LiveConnection(portPath: port)
        do {
            try conn.connect()
            sharedConnection = conn
        } catch {
            skipReason = "connect() failed on \(port): \(error.localizedDescription). " +
                         "Check Menu 985 = PC and radio is not busy."
        }
    }

    override class func tearDown() {
        sharedConnection?.disconnect()
        sharedConnection = nil
        super.tearDown()
    }

    /// Skip all CAT tests cleanly when hardware is absent.
    /// test_00_rawRead is exempt — it's a diagnostic that runs independently of sharedConnection.
    override func setUpWithError() throws {
        guard !name.contains("rawRead") else { return }
        if let reason = Self.skipReason { throw XCTSkip(reason) }
    }

    // Per-test connection accessor (skip guard is in setUpWithError above)
    private var conn: THD75LiveConnection {
        get throws { try XCTUnwrap(Self.sharedConnection) }
    }

    // MARK: - Diagnostic: raw read (run this first to verify data channel)

    /// Opens the port raw and reads any bytes the radio sends for 3 seconds,
    /// WITHOUT sending any command. This runs even when the class-level
    /// connect() failed, so we can see whether the data channel is alive.
    ///
    /// If 0 bytes: BT link may not be up yet, or radio isn't transmitting.
    /// If NMEA/APRS data: radio BT output mode is GPS/APRS — set Menu 985 = PC.
    /// If anything: data channel is alive and the ID probe timing needs tuning.
    func test_00_rawRead_dataChannelAlive() throws {
        // If connect() already succeeded, the port is held exclusively — skip the
        // raw open attempt (which would fail with EBUSY) and count it as a pass.
        if Self.sharedConnection != nil {
            throw XCTSkip("connect() already succeeded — data channel confirmed alive")
        }
        guard let port = Self.findRadioPort() else {
            throw XCTSkip("No TH-D74/D75 port in /dev — radio off or not paired")
        }

        let rawPort = SerialPort(path: port)
        try rawPort.open(baudRate: 9600, hardwareFlowControl: false, twoStopBits: false)
        defer { rawPort.close() }

        // Give the BT link time to establish after port open
        Thread.sleep(forTimeInterval: 3.0)

        // Passive read — CAT mode is silent until commanded
        let passiveRaw = (try? rawPort.readAvailable(maxCount: 256, timeout: 2.0)) ?? Data()
        print("\n📻 Passive read (\(passiveRaw.count) bytes): \(Self.printable(passiveRaw))")

        // Active probe — send ID\r and read raw response
        try rawPort.write(Data("ID\r".utf8))
        Thread.sleep(forTimeInterval: 0.5)
        let activeRaw  = (try? rawPort.readAvailable(maxCount: 64, timeout: 2.0)) ?? Data()
        let activeHex  = activeRaw.map { String(format: "%02X", $0) }.joined(separator: " ")
        print("📻 ID\\r response  (\(activeRaw.count) bytes): \(Self.printable(activeRaw))")
        print("📻 ID\\r hex       : \(activeHex)\n")

        // If 0 bytes back, the most common cause on macOS is TCC Bluetooth permission
        // being denied for the swift test runner process.
        // To fix: System Settings → Privacy & Security → Bluetooth → add Terminal.
        // The app itself (TH-Programmer.app) has its own BT permission and is unaffected.
        if activeRaw.isEmpty {
            throw XCTSkip(
                "0 bytes returned on \(port) — likely macOS TCC Bluetooth permission denied " +
                "for the test runner. To fix: System Settings → Privacy & Security → Bluetooth " +
                "→ grant access to Terminal (or re-run from the app). " +
                "Also check Menu 985 = PC on the radio."
            )
        }
        XCTAssertGreaterThan(activeRaw.count, 0)
    }

    private static func printable(_ data: Data) -> String {
        (String(data: data, encoding: .ascii) ?? "(non-ASCII)")
            .replacingOccurrences(of: "\r", with: "↵")
            .replacingOccurrences(of: "\n", with: "↵")
    }

    // MARK: - Connection

    func testConnect_identifiesRadio() throws {
        _ = try conn   // skip if no hardware; non-nil means connect() succeeded
    }

    // MARK: - VFO State

    func testGetVFOState_frequencyInValidRange() throws {
        let state = try conn.getVFOState(vfo: 0)
        XCTAssertGreaterThan(state.frequencyHz, 1_000_000,
                             "Frequency should be > 1 MHz, got \(state.frequencyHz) Hz")
        XCTAssertLessThan(state.frequencyHz, 1_000_000_000,
                          "Frequency should be < 1 GHz, got \(state.frequencyHz) Hz")
    }

    func testGetVFOState_modeIsKnown() throws {
        let state = try conn.getVFOState(vfo: 0)
        XCTAssertLessThan(Int(state.mode), LiveRadioState.modeNames.count,
                          "Mode index \(state.mode) exceeds known mode table")
    }

    func testGetVFOState_vfoFieldMatchesRequest() throws {
        let stateA = try conn.getVFOState(vfo: 0)
        let stateB = try conn.getVFOState(vfo: 1)
        XCTAssertEqual(stateA.vfo, 0)
        XCTAssertEqual(stateB.vfo, 1)
    }

    func testGetVFOState_frequencyMHzFormatted() throws {
        let state = try conn.getVFOState(vfo: 0)
        let mhz = Double(state.frequencyMHz)
        XCTAssertNotNil(mhz)
        XCTAssertGreaterThan(mhz ?? 0, 0)
    }

    // MARK: - Radio Info

    func testGetRadioInfo_firmwareVersionNonEmpty() throws {
        let info = try conn.getRadioInfo()
        XCTAssertFalse(info.firmwareVersion.isEmpty)
    }

    func testGetRadioInfo_serialNumberNonEmpty() throws {
        let info = try conn.getRadioInfo()
        XCTAssertFalse(info.serialNumber.isEmpty)
    }

    func testGetRadioInfo_callsignNonEmpty() throws {
        let info = try conn.getRadioInfo()
        XCTAssertFalse(info.callsign.isEmpty,
                       "Callsign empty — program one via Menu if not set")
    }

    func testGetRadioInfo_clockStringLength() throws {
        let info = try conn.getRadioInfo()
        guard !info.clockString.isEmpty else { return }
        XCTAssertEqual(info.clockString.count, 12,
                       "RT clock string should be 12 chars (YYMMDDHHMMSS), got '\(info.clockString)'")
    }

    func testGetRadioInfo_clockFormatsParseable() throws {
        let info = try conn.getRadioInfo()
        guard !info.clockString.isEmpty else { return }
        let formatted = THD75LiveConnection.formatClockString(info.clockString)
        XCTAssertNotNil(formatted)
    }

    // MARK: - Live Settings

    func testGetAFGain_inRange() throws {
        let gain = try conn.getAFGain()
        XCTAssertLessThanOrEqual(gain, 100)
    }

    func testGetBacklight_inRange() throws {
        let level = try conn.getBacklight()
        XCTAssertLessThanOrEqual(level, 6)
    }

    func testGetBusy_doesNotThrow() throws {
        XCTAssertNoThrow(try conn.getBusy(vfo: 0))
    }

    func testGetSquelch_inRange() throws {
        let sq = try conn.getSquelch(vfo: 0)
        XCTAssertLessThanOrEqual(sq, 31)
    }

    // getDialLock removed — LK command not supported on D75 firmware 1.03

    func testGetVOX_doesNotThrow() throws {
        XCTAssertNoThrow(try conn.getVOX())
    }

    // MARK: - Roundtrip write (safe: restores original)

    func testAFGain_roundtrip() throws {
        let original = try conn.getAFGain()
        let testValue: UInt8 = original == 50 ? 51 : 50
        try conn.setAFGain(testValue)
        XCTAssertEqual(try conn.getAFGain(), testValue)
        try conn.setAFGain(original)
        XCTAssertEqual(try conn.getAFGain(), original)
    }

    // getBeep/setBeep removed — BP command not supported on D75 firmware 1.03

    // MARK: - Active VFO

    func testActiveVFO_inRange() throws {
        let vfo = try conn.activeVFO()
        XCTAssertTrue(vfo == 0 || vfo == 1)
    }

    // MARK: - TX Power (PC command)

    func testGetTxPower_bandA_inRange() throws {
        let power = try conn.getTxPower(band: 0)
        XCTAssertLessThanOrEqual(power, 3,
                                 "Power level should be 0–3 (H/M/L/EL), got \(power)")
    }

    func testGetTxPower_bandB_inRange() throws {
        let power = try conn.getTxPower(band: 1)
        XCTAssertLessThanOrEqual(power, 3)
    }

    func testTxPower_roundtrip() throws {
        let original = try conn.getTxPower(band: 0)
        let testLevel: UInt8 = original == 0 ? 2 : 0
        try conn.setTxPower(band: 0, level: testLevel)
        XCTAssertEqual(try conn.getTxPower(band: 0), testLevel)
        // Restore
        try conn.setTxPower(band: 0, level: original)
        XCTAssertEqual(try conn.getTxPower(band: 0), original)
    }

    // MARK: - D-STAR Callsign Slots (DC/DS commands)

    func testGetDStarSlot_doesNotThrow() throws {
        XCTAssertNoThrow(try conn.getDStarSlot(1))
    }

    func testDStarSlot6_roundtrip() throws {
        // Read whatever is in slot 6, write a test value, verify, restore.
        let original = try conn.getDStarSlot(6)
        try conn.setDStarSlot(6, callsign: "TEST")
        let changed = try conn.getDStarSlot(6)
        XCTAssertEqual(changed, "TEST")
        // Restore
        try conn.setDStarSlot(6, callsign: original)
    }

    func testGetActiveDStarSlot_inRange() throws {
        let slot = try conn.getActiveDStarSlot()
        XCTAssertGreaterThanOrEqual(slot, 1)
        XCTAssertLessThanOrEqual(slot, 6)
    }

    func testActiveDStarSlot_roundtrip() throws {
        let original = try conn.getActiveDStarSlot()
        let testSlot: UInt8 = original == 1 ? 2 : 1
        try conn.setActiveDStarSlot(testSlot)
        XCTAssertEqual(try conn.getActiveDStarSlot(), testSlot)
        // Restore
        try conn.setActiveDStarSlot(original)
        XCTAssertEqual(try conn.getActiveDStarSlot(), original)
    }

    // MARK: - APRS Beacon (BE command)

    func testTriggerAPRSBeacon_returnsResult() throws {
        // Returns true (beacon sent) or false (TNC off) — either is valid.
        let result = try conn.triggerAPRSBeacon()
        XCTAssertTrue(result == true || result == false)
    }

    // MARK: - Bluetooth (BT command)

    func testGetBluetooth_doesNotThrow() throws {
        // Read-only: setBluetooth(false) over BT would kill the connection.
        let bt = try conn.getBluetooth()
        // If we're connected over Bluetooth, this should be true.
        // Over USB cable it could be either. Just verify it doesn't throw.
        XCTAssertTrue(bt == true || bt == false)
    }

    // MARK: - TNC Baud Rate (AS command)

    func testGetTNCBaudRate_inRange() throws {
        let rate = try conn.getTNCBaudRate()
        XCTAssertTrue(rate == 0 || rate == 1,
                      "TNC baud should be 0 (1200) or 1 (9600), got \(rate)")
    }

    func testTNCBaudRate_roundtrip() throws {
        let original = try conn.getTNCBaudRate()
        let testValue: UInt8 = original == 0 ? 1 : 0
        try conn.setTNCBaudRate(testValue)
        XCTAssertEqual(try conn.getTNCBaudRate(), testValue)
        // Restore
        try conn.setTNCBaudRate(original)
        XCTAssertEqual(try conn.getTNCBaudRate(), original)
    }

    // MARK: - Helpers

    static func findRadioPort() -> String? {
        guard let entries = try? FileManager.default.contentsOfDirectory(atPath: "/dev")
        else { return nil }
        let cuEntries = entries.filter { $0.hasPrefix("cu.") }.sorted()
        // Bluetooth SPP: cu.TH-D75 / cu.TH-D74 by device name (requires BT TCC permission)
        if let bt = cuEntries.first(where: { $0.contains("TH-D75") || $0.contains("TH-D74") }) {
            return "/dev/\(bt)"
        }
        // USB: probe each usbserial/usbmodem port with ID\r to find the actual radio
        // (avoids grabbing the CTR2-MIDI or other non-radio USB serial devices)
        let usbCandidates = cuEntries.filter { $0.hasPrefix("cu.usbserial") || $0.hasPrefix("cu.usbmodem") }
        for entry in usbCandidates {
            let path = "/dev/\(entry)"
            if probeForRadio(path: path) { return path }
        }
        // Bluetooth SPP: generic address-based match
        return cuEntries
            .first { BluetoothManager.portEntryMatches($0, deviceName: "", addressSuffix: "") }
            .map { "/dev/\($0)" }
    }

    /// Send ID\r at 9600 baud and check if the response contains "TH-D7".
    private static func probeForRadio(path: String) -> Bool {
        let port = SerialPort(path: path)
        defer { port.close() }
        do {
            try port.open(baudRate: 9600, hardwareFlowControl: false, twoStopBits: false)
            try port.write(Data("ID\r".utf8))
            Thread.sleep(forTimeInterval: 0.5)
            guard let data = try? port.readAvailable(maxCount: 64, timeout: 1.0),
                  let response = String(data: data, encoding: .ascii) else { return false }
            return response.contains("TH-D7")
        } catch {
            return false
        }
    }
}

