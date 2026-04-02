// SerialPortDiscoveryTests.swift — Tests for serial port enumeration and scoring

import XCTest
@testable import TH_Programmer

final class SerialPortDiscoveryTests: XCTestCase {
    nonisolated deinit {}

    func testDiscover_emptyDirectory() {
        let ports = SerialPortDiscovery.ports(from: [])
        XCTAssertTrue(ports.isEmpty)
    }

    func testDiscover_filtersTTYAndCU() {
        let entries = ["cu.usbmodem001", "tty.usbmodem001", "disk0", "null"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.count, 2)
    }

    func testDiscover_scoresTHD75Highest() {
        let entries = ["cu.TH-D75-SPP", "cu.usbmodem001", "cu.Bluetooth-Incoming-Port"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.displayName, "cu.TH-D75-SPP")
    }

    func testDiscover_scoresKenwoodAboveBluetooth() {
        let entries = ["cu.Kenwood-SPP", "cu.GenericBluetooth"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.displayName, "cu.Kenwood-SPP")
    }

    func testDiscover_penalizesIncomingPort() {
        let entries = ["cu.Bluetooth-Incoming-Port", "cu.usbmodem001"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.last?.displayName, "cu.Bluetooth-Incoming-Port")
    }

    func testDiscover_sortsByScoreDescending() {
        let entries = ["cu.generic", "cu.TH-D75-Serial", "tty.usbmodem001"]
        let ports = SerialPortDiscovery.ports(from: entries)
        // TH-D75 should be first (highest score)
        XCTAssertEqual(ports.first?.displayName, "cu.TH-D75-Serial")
        // cu.generic should be before tty. (cu gets +80)
        let genericIndex = ports.firstIndex { $0.displayName == "cu.generic" }
        let ttyIndex = ports.firstIndex { $0.displayName == "tty.usbmodem001" }
        XCTAssertNotNil(genericIndex)
        XCTAssertNotNil(ttyIndex)
        if let g = genericIndex, let t = ttyIndex {
            XCTAssertLessThan(g, t)
        }
    }

    func testDiscover_detectsBluetoothSPP() {
        let entries = ["cu.Bluetooth-Device"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.transportKind, .bluetoothSPP)
    }

    func testDiscover_detectsUSBCDC() {
        let entries = ["cu.usbmodem12345"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.transportKind, .usbCDC)
    }

    func testDiscover_unknownTransportKind() {
        let entries = ["cu.generic-serial"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.transportKind, .unknown)
    }

    func testDiscover_pathIncludesDeviceRoot() {
        let entries = ["cu.test"]
        let ports = SerialPortDiscovery.ports(from: entries, deviceRoot: "/dev")
        XCTAssertEqual(ports.first?.path, "/dev/cu.test")
    }

    func testDiscover_detectsRFCOMM() {
        let entries = ["cu.rfcomm-device"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.transportKind, .bluetoothSPP)
    }

    func testDiscover_detectsUSBSerial() {
        let entries = ["cu.usbserial-001"]
        let ports = SerialPortDiscovery.ports(from: entries)
        XCTAssertEqual(ports.first?.transportKind, .usbCDC)
    }
}
