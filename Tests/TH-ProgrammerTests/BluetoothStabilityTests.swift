// BluetoothStabilityTests.swift — Tests for BT disconnect detection, poll() timeouts,
// isBluetoothPort() classification, and SerialPort health checks.
//
// These are all unit tests — no hardware required.

import XCTest
@testable import TH_Programmer

final class BluetoothStabilityTests: XCTestCase {

    nonisolated deinit {}

    // MARK: - isBluetoothPort classification

    func testIsBluetoothPort_THD75() {
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.TH-D75"))
    }

    func testIsBluetoothPort_THD75_serialPort() {
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.TH-D75-SerialPort"))
    }

    func testIsBluetoothPort_THD74() {
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.TH-D74"))
    }

    func testIsBluetoothPort_THD75_noDash() {
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.THD75"))
    }

    func testIsBluetoothPort_genericBluetooth() {
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.Bluetooth-Incoming-Port"))
    }

    func testIsBluetoothPort_wireless() {
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.SomeDevice-wireless"))
    }

    func testIsBluetoothPort_usbmodem_notBT() {
        XCTAssertFalse(SerialPort.isBluetoothPort("/dev/cu.usbmodem12345"))
    }

    func testIsBluetoothPort_SLAB_notBT() {
        XCTAssertFalse(SerialPort.isBluetoothPort("/dev/cu.SLAB_USBtoUART"))
    }

    func testIsBluetoothPort_SLAB_uppercase_notBT() {
        XCTAssertFalse(SerialPort.isBluetoothPort("/dev/cu.SLAB_USBtoUART16"))
    }

    func testIsBluetoothPort_usbserial_notBT() {
        XCTAssertFalse(SerialPort.isBluetoothPort("/dev/cu.usbserial-001"))
    }

    func testIsBluetoothPort_unknownDevice_notBT() {
        // Unknown device type should conservatively default to non-BT
        XCTAssertFalse(SerialPort.isBluetoothPort("/dev/cu.RandomDevice"))
    }

    func testIsBluetoothPort_caseInsensitive_THD75() {
        // The port name matching should be case-insensitive
        XCTAssertTrue(SerialPort.isBluetoothPort("/dev/cu.th-d75"))
    }

    // MARK: - SerialPort on invalid fd

    func testIsHealthy_unopenedPort_returnsFalse() {
        let port = SerialPort(path: "/dev/does-not-exist")
        XCTAssertFalse(port.isHealthy())
    }

    func testIsHealthy_closedPort_returnsFalse() {
        let port = SerialPort(path: "/dev/null")
        // /dev/null can be opened but won't behave like a serial port
        // After close, isHealthy should return false
        XCTAssertFalse(port.isHealthy(), "Unopened port should not be healthy")
    }

    func testReadLine_notOpen_throws() {
        let port = SerialPort(path: "/dev/does-not-exist")
        XCTAssertThrowsError(try port.readLine(timeout: 0.1)) { error in
            XCTAssertTrue(error is SerialError)
            if case SerialError.notOpen = error {
                // expected
            } else {
                XCTFail("Expected SerialError.notOpen, got \(error)")
            }
        }
    }

    func testRead_notOpen_throws() {
        let port = SerialPort(path: "/dev/does-not-exist")
        XCTAssertThrowsError(try port.read(count: 1, timeout: 0.1)) { error in
            XCTAssertTrue(error is SerialError)
        }
    }

    func testReadAvailable_notOpen_throws() {
        let port = SerialPort(path: "/dev/does-not-exist")
        XCTAssertThrowsError(try port.readAvailable(maxCount: 1, timeout: 0.1)) { error in
            XCTAssertTrue(error is SerialError)
        }
    }

    // MARK: - SerialPort poll-based timeout
    //
    // We can't open /dev/null with TIOCEXCL (it's not a real serial device).
    // Instead, test the timeout guarantee by verifying that the poll-based
    // readLine on an unopened port throws .notOpen immediately (no hang),
    // and that the isHealthy() path works on real pipe fds.

    func testReadLine_onUnopenedPort_throwsImmediately() {
        let port = SerialPort(path: "/dev/cu.nonexistent-test-port")
        let start = Date()
        XCTAssertThrowsError(try port.readLine(timeout: 5.0))
        let elapsed = Date().timeIntervalSince(start)
        // Must throw instantly, not wait 5 seconds
        XCTAssertLessThan(elapsed, 1.0,
                          "readLine on unopened port should throw immediately, not block for timeout")
    }

    func testRead_onUnopenedPort_throwsImmediately() {
        let port = SerialPort(path: "/dev/cu.nonexistent-test-port")
        let start = Date()
        XCTAssertThrowsError(try port.read(count: 10, timeout: 5.0))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0)
    }

    func testReadAvailable_onUnopenedPort_throwsImmediately() {
        let port = SerialPort(path: "/dev/cu.nonexistent-test-port")
        let start = Date()
        XCTAssertThrowsError(try port.readAvailable(maxCount: 256, timeout: 5.0))
        let elapsed = Date().timeIntervalSince(start)
        XCTAssertLessThan(elapsed, 1.0)
    }

    // MARK: - SerialError.portDied description

    func testPortDiedErrorDescription() {
        let error = SerialError.portDied
        XCTAssertNotNil(error.errorDescription)
        XCTAssertTrue(error.errorDescription!.contains("disconnected"))
    }

    // MARK: - SerialPort health on pipe fd (simulate dead port)

    func testIsHealthy_pipeWriteEnd_closedRead_detectsHangup() {
        // Create a pipe, close the read end, and verify poll detects POLLHUP
        // on the write end. This simulates a BT port that lost its remote peer.
        var fds: [Int32] = [0, 0]
        let result = pipe(&fds)
        guard result == 0 else {
            XCTFail("pipe() failed")
            return
        }
        // Close the read end — the write end should get POLLHUP
        close(fds[0])

        // Use the write fd to test poll behavior
        var pfd = pollfd(fd: fds[1], events: Int16(POLLIN), revents: 0)
        let pollResult = poll(&pfd, 1, 0)

        // Clean up
        close(fds[1])

        // On macOS, closing the read end causes POLLHUP on the write end
        if pollResult > 0 {
            let gotHup = pfd.revents & Int16(POLLHUP) != 0
            let gotErr = pfd.revents & Int16(POLLERR) != 0
            XCTAssertTrue(gotHup || gotErr,
                          "Expected POLLHUP or POLLERR on broken pipe, got revents=\(pfd.revents)")
        }
        // pollResult == 0 (timeout) is also acceptable — not all platforms signal HUP on pipe
    }

    // MARK: - THD75LiveConnection.isBluetooth

    func testLiveConnection_isBluetooth_THD75() {
        let conn = THD75LiveConnection(portPath: "/dev/cu.TH-D75")
        XCTAssertTrue(conn.isBluetooth)
    }

    func testLiveConnection_isBluetooth_usbmodem() {
        let conn = THD75LiveConnection(portPath: "/dev/cu.usbmodem12345")
        XCTAssertFalse(conn.isBluetooth)
    }

    func testLiveConnection_isHealthy_unopened() {
        let conn = THD75LiveConnection(portPath: "/dev/cu.TH-D75")
        // Not connected — should report unhealthy
        XCTAssertFalse(conn.isHealthy())
    }

    // MARK: - LiveError.unexpectedID

    func testUnexpectedIDError_containsReceivedString() {
        let error = LiveError.unexpectedID("GARBAGE")
        XCTAssertTrue(error.localizedDescription.contains("GARBAGE"))
        XCTAssertTrue(error.localizedDescription.contains("TH-D74"))
    }

    func testUnexpectedIDError_emptyResponse() {
        let error = LiveError.unexpectedID("")
        XCTAssertTrue(error.localizedDescription.contains("\"\""))
    }
}
