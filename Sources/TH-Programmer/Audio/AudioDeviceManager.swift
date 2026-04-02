// AudioDeviceManager.swift — CoreAudio device enumeration and monitoring

import Foundation
import CoreAudio
import AudioToolbox

/// Represents an audio device on the system.
struct AudioDevice: Identifiable, Equatable, Hashable, Sendable {
    let id: AudioDeviceID
    let name: String
    let isInput: Bool
    let isOutput: Bool

    /// True if this appears to be the TH-D75 USB audio interface.
    var isRadioUSBAudio: Bool {
        let upper = name.uppercased()
        return (upper.contains("TH-D7") || upper.contains("KENWOOD"))
            && !isRadioBluetoothAudio
    }

    /// True if this appears to be TH-D75 Bluetooth audio (HFP/A2DP).
    var isRadioBluetoothAudio: Bool {
        let upper = name.uppercased()
        let isRadio = upper.contains("TH-D75") || upper.contains("THD75")
            || upper.contains("TH-D74") || upper.contains("THD74")
        let isBluetooth = upper.contains("BLUETOOTH")
        return isRadio && isBluetooth
    }
}

/// Enumerates and monitors CoreAudio input/output devices.
final class AudioDeviceManager: @unchecked Sendable {

    nonisolated deinit {}

    /// Called when the device list changes.
    var onDevicesChanged: (() -> Void)?

    private var listenerBlock: AudioObjectPropertyListenerBlock?

    init() {
        startMonitoring()
    }

    // MARK: - Device Enumeration

    /// Get all audio devices on the system.
    func allDevices() -> [AudioDevice] {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        var status = AudioObjectGetPropertyDataSize(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize
        )
        guard status == noErr, dataSize > 0 else { return [] }

        let deviceCount = Int(dataSize) / MemoryLayout<AudioDeviceID>.size
        var deviceIDs = [AudioDeviceID](repeating: 0, count: deviceCount)

        status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceIDs
        )
        guard status == noErr else { return [] }

        return deviceIDs.compactMap { deviceID -> AudioDevice? in
            let name = deviceName(deviceID)
            guard !name.isEmpty else { return nil }
            let hasInput = hasStreams(deviceID, scope: kAudioDevicePropertyScopeInput)
            let hasOutput = hasStreams(deviceID, scope: kAudioDevicePropertyScopeOutput)
            guard hasInput || hasOutput else { return nil }
            return AudioDevice(id: deviceID, name: name, isInput: hasInput, isOutput: hasOutput)
        }
    }

    /// Get input devices only.
    func inputDevices() -> [AudioDevice] {
        allDevices().filter(\.isInput)
    }

    /// Get output devices only.
    func outputDevices() -> [AudioDevice] {
        allDevices().filter(\.isOutput)
    }

    // MARK: - Radio Device Detection

    /// First input device that appears to be TH-D75 USB audio.
    func radioUSBInputDevice() -> AudioDevice? {
        inputDevices().first(where: \.isRadioUSBAudio)
    }

    /// First output device that appears to be TH-D75 USB audio.
    func radioUSBOutputDevice() -> AudioDevice? {
        outputDevices().first(where: \.isRadioUSBAudio)
    }

    /// First input device that appears to be TH-D75 Bluetooth audio.
    func radioBluetoothInputDevice() -> AudioDevice? {
        inputDevices().first(where: \.isRadioBluetoothAudio)
    }

    /// First output device that appears to be TH-D75 Bluetooth audio.
    func radioBluetoothOutputDevice() -> AudioDevice? {
        outputDevices().first(where: \.isRadioBluetoothAudio)
    }

    /// Get the system default input device.
    func defaultInputDevice() -> AudioDeviceID? {
        getDefaultDevice(selector: kAudioHardwarePropertyDefaultInputDevice)
    }

    /// Get the system default output device.
    func defaultOutputDevice() -> AudioDeviceID? {
        getDefaultDevice(selector: kAudioHardwarePropertyDefaultOutputDevice)
    }

    // MARK: - Device Properties

    private func deviceName(_ deviceID: AudioDeviceID) -> String {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyDeviceNameCFString,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var name: CFString = "" as CFString
        var dataSize = UInt32(MemoryLayout<CFString>.size)

        let status = AudioObjectGetPropertyData(
            deviceID,
            &address,
            0, nil,
            &dataSize,
            &name
        )
        guard status == noErr else { return "" }
        return name as String
    }

    private func hasStreams(_ deviceID: AudioDeviceID, scope: AudioObjectPropertyScope) -> Bool {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioDevicePropertyStreams,
            mScope: scope,
            mElement: kAudioObjectPropertyElementMain
        )

        var dataSize: UInt32 = 0
        let status = AudioObjectGetPropertyDataSize(deviceID, &address, 0, nil, &dataSize)
        return status == noErr && dataSize > 0
    }

    private func getDefaultDevice(selector: AudioObjectPropertySelector) -> AudioDeviceID? {
        var address = AudioObjectPropertyAddress(
            mSelector: selector,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        var deviceID: AudioDeviceID = 0
        var dataSize = UInt32(MemoryLayout<AudioDeviceID>.size)

        let status = AudioObjectGetPropertyData(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            0, nil,
            &dataSize,
            &deviceID
        )
        guard status == noErr, deviceID != 0 else { return nil }
        return deviceID
    }

    // MARK: - Device Change Monitoring

    private func startMonitoring() {
        var address = AudioObjectPropertyAddress(
            mSelector: kAudioHardwarePropertyDevices,
            mScope: kAudioObjectPropertyScopeGlobal,
            mElement: kAudioObjectPropertyElementMain
        )

        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            self?.onDevicesChanged?()
        }
        listenerBlock = block

        AudioObjectAddPropertyListenerBlock(
            AudioObjectID(kAudioObjectSystemObject),
            &address,
            DispatchQueue.main,
            block
        )
    }
}
