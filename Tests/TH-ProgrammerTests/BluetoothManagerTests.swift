// BluetoothManagerTests.swift — Unit tests for BluetoothManager pure-logic helpers

import XCTest
@testable import TH_Programmer

final class BluetoothManagerTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - BluetoothRadio.statusLabel

    func testStatusLabel_portPath() {
        let radio = BluetoothRadio(
            name: "TH-D75",
            addressString: "AA:BB:CC:DD:EE:FF",
            isConnected: true,
            portPath: "/dev/cu.TH-D75-SerialPort"
        )
        XCTAssertEqual(radio.statusLabel, "Ready — cu.TH-D75-SerialPort")
    }

    func testStatusLabel_connectedNoPort() {
        let radio = BluetoothRadio(
            name: "TH-D75",
            addressString: "AA:BB:CC:DD:EE:FF",
            isConnected: true,
            portPath: nil
        )
        XCTAssertEqual(radio.statusLabel, "Connected (waiting for serial port…)")
    }

    func testStatusLabel_notConnected() {
        let radio = BluetoothRadio(
            name: "TH-D75",
            addressString: "AA:BB:CC:DD:EE:FF",
            isConnected: false,
            portPath: nil
        )
        XCTAssertEqual(radio.statusLabel, "Not connected")
    }

    // MARK: - BluetoothRadio.id

    func testRadioID_equalsAddressString() {
        let radio = BluetoothRadio(
            name: "TH-D75",
            addressString: "11:22:33:44:55:66",
            isConnected: false,
            portPath: nil
        )
        XCTAssertEqual(radio.id, "11:22:33:44:55:66")
    }

    // MARK: - isSupportedRadioName

    func testSupportedName_THD75_uppercase() {
        XCTAssertTrue(BluetoothManager.isSupportedRadioName("TH-D75"))
    }

    func testSupportedName_THD74_uppercase() {
        XCTAssertTrue(BluetoothManager.isSupportedRadioName("TH-D74"))
    }

    func testSupportedName_THD75_noDash() {
        XCTAssertTrue(BluetoothManager.isSupportedRadioName("THD75"))
    }

    func testSupportedName_THD74_noDash() {
        XCTAssertTrue(BluetoothManager.isSupportedRadioName("THD74"))
    }

    func testSupportedName_lowercase() {
        XCTAssertTrue(BluetoothManager.isSupportedRadioName("th-d75 amateur transceiver"))
    }

    func testSupportedName_mixedCase() {
        XCTAssertTrue(BluetoothManager.isSupportedRadioName("Kenwood TH-D75A"))
    }

    func testSupportedName_CTR2_rejected() {
        XCTAssertFalse(BluetoothManager.isSupportedRadioName("CTR2 MIDI Controller"))
    }

    func testSupportedName_empty_rejected() {
        XCTAssertFalse(BluetoothManager.isSupportedRadioName(""))
    }

    func testSupportedName_unrelatedDevice_rejected() {
        XCTAssertFalse(BluetoothManager.isSupportedRadioName("AirPods Pro"))
    }

    // MARK: - portEntryMatches — keyword fallback

    func testPortMatch_keyword_THD75() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.TH-D75-SerialPort", deviceName: "", addressSuffix: ""))
    }

    func testPortMatch_keyword_THD75_noDash() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.THD75", deviceName: "", addressSuffix: ""))
    }

    func testPortMatch_keyword_THD74() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.TH-D74", deviceName: "", addressSuffix: ""))
    }

    func testPortMatch_keyword_THD74_noDash() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.THD74", deviceName: "", addressSuffix: ""))
    }

    // MARK: - portEntryMatches — device name slug

    func testPortMatch_nameSlug_exact() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.TH-D75A-SerialPort", deviceName: "TH-D75A", addressSuffix: ""))
    }

    func testPortMatch_nameSlug_withSpaces() {
        // Device name "Kenwood TH-D75" → slug "kenwood-th-d75"
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.Kenwood-TH-D75", deviceName: "Kenwood TH-D75", addressSuffix: ""))
    }

    func testPortMatch_nameSlug_caseInsensitive() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.th-d75-serialport", deviceName: "TH-D75", addressSuffix: ""))
    }

    // MARK: - portEntryMatches — address suffix

    func testPortMatch_addressSuffix() {
        // macOS sometimes names the port after the BT address
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.aa-bb-cc-dd-ee-ff", deviceName: "", addressSuffix: "AA-BB-CC-DD-EE-FF"))
    }

    func testPortMatch_addressSuffix_caseInsensitive() {
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "cu.AA-BB-CC-DD-EE-FF", deviceName: "", addressSuffix: "aa-bb-cc-dd-ee-ff"))
    }

    // MARK: - portEntryMatches — non-matching ports

    func testPortMatch_usbmodem_rejected() {
        XCTAssertFalse(BluetoothManager.portEntryMatches(
            "cu.usbmodem12345", deviceName: "", addressSuffix: ""))
    }

    func testPortMatch_SLAB_rejected() {
        XCTAssertFalse(BluetoothManager.portEntryMatches(
            "cu.SLAB_USBtoUART", deviceName: "", addressSuffix: ""))
    }

    func testPortMatch_Bluetooth_generic_rejected() {
        // A generic BT port with no radio-specific keyword should not match
        XCTAssertFalse(BluetoothManager.portEntryMatches(
            "cu.Bluetooth-PDA-Sync", deviceName: "", addressSuffix: ""))
    }

    func testPortMatch_emptyName_emptyAddr_noKeyword_rejected() {
        XCTAssertFalse(BluetoothManager.portEntryMatches(
            "cu.RandomDevice", deviceName: "", addressSuffix: ""))
    }

    // MARK: - portEntryMatches — prefix filtering is findPort's responsibility

    func testPortMatch_ttyPrefix_notProbed() {
        // portEntryMatches does NOT enforce the "cu." prefix — that guard lives in
        // findPort, which only passes entries that already start with "cu.".
        // A "tty.*" entry with a matching name slug WILL return true here; the
        // caller is responsible for pre-filtering to cu.* before calling this.
        XCTAssertTrue(BluetoothManager.portEntryMatches(
            "tty.TH-D75", deviceName: "TH-D75", addressSuffix: ""),
            "portEntryMatches matches on name slug regardless of cu./tty. prefix")
    }
}
