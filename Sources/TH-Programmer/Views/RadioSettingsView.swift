// RadioSettingsView.swift — Radio-wide settings editor
// Covers all options from the Java TH-D75 Programmer RadioSettings tab

import SwiftUI

// MARK: - Standalone sheet (Save/Cancel/Revert toolbar)

struct RadioSettingsView: View {
    @EnvironmentObject var store: RadioStore
    @Environment(\.dismiss) private var dismiss

    @State private var settings: RadioSettings
    private let original: RadioSettings

    init(settings: RadioSettings) {
        _settings = State(initialValue: settings)
        original = settings
    }

    var body: some View {
        NavigationStack {
            RadioSettingsForm(settings: $settings)
                .navigationTitle("Radio Settings")
                .toolbar {
                    ToolbarItem(placement: .confirmationAction) {
                        Button("Save") {
                            store.applyRadioSettings(settings)
                            dismiss()
                        }
                        .accessibilityLabel("Save radio settings to image")
                    }
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .navigation) {
                        Button("Revert") {
                            settings = original
                            store.announceAccessibility("Settings reverted to last saved values.")
                        }
                        .accessibilityLabel("Revert all settings to last saved values")
                        .disabled(settings == original)
                    }
                }
        }
        .frame(minWidth: 520, minHeight: 600)
    }
}

// MARK: - Embeddable form (used by Settings tab)

struct RadioSettingsForm: View {
    @Binding var settings: RadioSettings

    var body: some View {
        Form {
            radioSection
            scanSection
            voxSection
            dtmfSection
            cwSection
            displaySection
            audioSection
            powerBluetoothSection
            pfKeysSection
            lockSection
            unitsSection
            interfaceSection
            pcInterfaceSection
            txPowerSection
        }
        .formStyle(.grouped)
    }

    // MARK: - Radio

    private var radioSection: some View {
        Section("Radio") {
            Toggle("Beat Shift", isOn: $settings.beatShift)
                .accessibilityLabel("Beat shift, reduces interference from display")

            Toggle("TX Inhibit", isOn: $settings.txInhibit)
                .accessibilityLabel("TX inhibit, disables transmit")

            pickerRow("Time Out Timer", selection: $settings.timeOutTimer,
                      options: RadioSettings.timeOutTimerOptions,
                      label: "Time out timer, auto-disables TX after selected time")

            Toggle("Auto Repeater Shift", isOn: $settings.autoRepeaterShift)

            pickerRow("Mic Sensitivity", selection: $settings.micSensitivity,
                      options: RadioSettings.micSensOptions,
                      label: "Microphone sensitivity level")

            Toggle("WX Alert", isOn: $settings.wxAlert)
                .accessibilityLabel("Weather alert, sounds alarm on WX channels")

            Picker("SSB High-Cut Filter", selection: $settings.ssbHighCut) {
                ForEach(Array(RadioSettings.ssbHighCutOptions.enumerated()), id: \.offset) { i, label in
                    Text(label).tag(UInt8(i))
                }
            }
            Picker("CW Width", selection: $settings.cwWidth) {
                ForEach(Array(RadioSettings.cwWidthOptions.enumerated()), id: \.offset) { i, label in
                    Text(label).tag(UInt8(i))
                }
            }
            Picker("AM High-Cut Filter", selection: $settings.amHighCut) {
                ForEach(Array(RadioSettings.amHighCutOptions.enumerated()), id: \.offset) { i, label in
                    Text(label).tag(UInt8(i))
                }
            }
            Picker("Bar Antenna", selection: $settings.barAntenna) {
                Text("External").tag(UInt8(0))
                Text("Internal").tag(UInt8(1))
            }
            .accessibilityLabel("Bar antenna selection")
            Toggle("Tone Burst Hold", isOn: $settings.toneBurstHold)
            Toggle("QSO Log", isOn: $settings.qsoLog)

            pickerRow("Detect Output", selection: $settings.detectOutSelect,
                      options: RadioSettings.detectOutOptions,
                      label: "Detect output select, AF output, IF output, or demodulator detect output")
        }
    }

    // MARK: - Scan

    private var scanSection: some View {
        Section("Scan") {
            pickerRow("Resume (Analog)", selection: $settings.scanResumeAnalog,
                      options: RadioSettings.scanResumeOptions,
                      label: "Analog scan resume timer")

            pickerRow("Resume (Digital)", selection: $settings.scanResumeDigital,
                      options: RadioSettings.scanResumeOptions,
                      label: "Digital scan resume timer")

            pickerRow("Priority Scan", selection: $settings.priorityScan,
                      options: RadioSettings.priorityScanOptions,
                      label: "Priority scan mode")

            Toggle("Auto Backlight on Scan", isOn: $settings.scanAutoBacklight)
            Toggle("Weather Auto Scan", isOn: $settings.scanWeatherAuto)
        }
    }

    // MARK: - VOX

    private var voxSection: some View {
        Section("VOX") {
            Toggle("VOX Enabled", isOn: $settings.voxEnabled)

            Stepper("VOX Gain: \(Int(settings.voxGain) + 1)",
                    value: $settings.voxGain, in: 0...9)
                .accessibilityLabel("VOX gain, level \(Int(settings.voxGain) + 1) of 10")
                .accessibilityValue("\(Int(settings.voxGain) + 1)")

            pickerRow("VOX Delay", selection: $settings.voxDelay,
                      options: RadioSettings.voxDelayOptions,
                      label: "VOX delay before TX drops")

            Stepper("VOX Hysteresis: \(settings.voxHysteresis)",
                    value: $settings.voxHysteresis, in: 0...9)
                .accessibilityLabel("VOX hysteresis level \(settings.voxHysteresis)")
        }
    }

    // MARK: - DTMF

    private var dtmfSection: some View {
        Section("DTMF") {
            pickerRow("Speed", selection: $settings.dtmfSpeed,
                      options: RadioSettings.dtmfSpeedOptions,
                      label: "DTMF tone speed")

            pickerRow("Hold Time", selection: $settings.dtmfHold,
                      options: RadioSettings.dtmfHoldOptions,
                      label: "DTMF tone hold time")

            pickerRow("Pause Time", selection: $settings.dtmfPause,
                      options: RadioSettings.dtmfPauseOptions,
                      label: "DTMF pause between tones")
        }
    }

    // MARK: - CW

    private var cwSection: some View {
        Section("CW") {
            pickerRow("CW Pitch", selection: $settings.cwPitch,
                      options: RadioSettings.cwPitchOptions,
                      label: "CW sidetone pitch frequency")

            Toggle("CW Reverse", isOn: $settings.cwReverse)
                .accessibilityLabel("CW reverse, swaps CW sidebands")
        }
    }

    // MARK: - Display

    private var displaySection: some View {
        Section("Display") {
            pickerRow("Backlight", selection: $settings.displayBacklight,
                      options: RadioSettings.backlightOptions,
                      label: "Display backlight mode")

            pickerRow("Brightness", selection: $settings.displayBrightness,
                      options: RadioSettings.brightnessOptions,
                      label: "Display brightness level")

            pickerRow("Single Band Info", selection: $settings.displaySingleBand,
                      options: RadioSettings.singleBandDisplayOptions,
                      label: "Information shown in single band display area")

            pickerRow("Meter Type", selection: $settings.displayMeterType,
                      options: RadioSettings.meterTypeOptions,
                      label: "S-meter display type")

            pickerRow("Background Color", selection: $settings.displayBgColor,
                      options: RadioSettings.bgColorOptions,
                      label: "Display background color")

            pickerRow("Info Backlight", selection: $settings.infoBacklight,
                      options: RadioSettings.infoBacklightOptions,
                      label: "Backlight mode for APRS/D-STAR interrupt and scan stop notifications")

            LabeledContent("Power-On Message") {
                TextField("Up to 16 characters", text: $settings.powerOnMessage)
                    .frame(width: 160)
                    .onChange(of: settings.powerOnMessage) { _, v in
                        if v.count > 16 { settings.powerOnMessage = String(v.prefix(16)) }
                    }
            }
            .accessibilityLabel("Power-on message displayed when radio starts, up to 16 characters")

            Toggle("RX LED", isOn: $settings.ledControlRx)
                .accessibilityLabel("RX LED, lights when receiving a signal")

            Toggle("FM Radio LED", isOn: $settings.ledControlFmRadio)
                .accessibilityLabel("FM Radio LED, lights when FM radio is active")
        }
    }

    // MARK: - Audio

    private var audioSection: some View {
        Section("Audio") {
            Stepper("Audio Balance: \(balanceLabel)",
                    value: $settings.audioBalance, in: 0...10)
                .accessibilityLabel("Audio balance, \(balanceLabel)")

            Toggle("Beep", isOn: $settings.beep)

            pickerRow("Beep Volume", selection: $settings.beepVolume,
                      options: RadioSettings.beepVolumeOptions,
                      label: "Beep volume level")
            .disabled(!settings.beep)

            pickerRow("Voice Guidance", selection: $settings.voiceGuidance,
                      options: RadioSettings.voiceGuidanceOptions,
                      label: "Voice guidance mode")

            pickerRow("Voice Guidance Speed", selection: $settings.voiceGuidanceSpeed,
                      options: RadioSettings.vgSpeedOptions,
                      label: "Voice guidance speed")

            pickerRow("Voice Guidance Volume", selection: $settings.voiceGuidanceVolume,
                      options: RadioSettings.voiceGuidanceVolumeOptions,
                      label: "Voice guidance volume level, VOL Link tracks main volume, or fixed Level 1 through 7")

            Toggle("USB Audio", isOn: $settings.usbAudio)
                .accessibilityLabel("USB audio output enable")

            Toggle("TX Audio Monitor", isOn: $settings.audioTxMonitor)

            pickerRow("USB Audio Output Level", selection: $settings.usbAudioOutputLevel,
                      options: RadioSettings.usbAudioOutputLevelOptions,
                      label: "USB audio output level, fixed Level 1 through 7")

            pickerRow("Recording Band", selection: $settings.audioRecordingBand,
                      options: RadioSettings.recordingBandOptions,
                      label: "Audio recording source band")

            pickerRow("Recall Method", selection: $settings.recallMethod,
                      options: RadioSettings.recallOptions,
                      label: "Memory recall method after recording")
        }
    }

    // MARK: - Power / Bluetooth

    private var powerBluetoothSection: some View {
        Section("Power & Bluetooth") {
            pickerRow("Battery Saver", selection: $settings.batterySaver,
                      options: RadioSettings.batterySaverOptions,
                      label: "Battery saver receiver shut-off interval")

            pickerRow("Auto Power Off", selection: $settings.autoPowerOff,
                      options: RadioSettings.autoPowerOffOptions,
                      label: "Automatic power off timer")

            Toggle("Bluetooth Enable", isOn: $settings.btEnabled)
                .accessibilityLabel("Bluetooth radio enable")

            Toggle("Bluetooth Auto-Connect", isOn: $settings.btAutoConnect)
                .disabled(!settings.btEnabled)

            pickerRow("Battery Charging", selection: $settings.batteryCharging,
                      options: RadioSettings.battChargingOptions,
                      label: "Battery charging mode")
        }
    }

    // MARK: - PF Keys

    private var pfKeysSection: some View {
        Section("Programmable Keys") {
            pfPicker("PF1 Key", selection: $settings.pf1Key,
                     label: "PF1 programmable function key assignment")
            pfPicker("PF2 Key", selection: $settings.pf2Key,
                     label: "PF2 programmable function key assignment")
            pfPicker("MIC PF1", selection: $settings.pf1MicKey,
                     label: "Microphone PF1 key assignment")
            pfPicker("MIC PF2", selection: $settings.pf2MicKey,
                     label: "Microphone PF2 key assignment")
            pfPicker("MIC PF3", selection: $settings.pf3MicKey,
                     label: "Microphone PF3 key assignment")
            Toggle("Cursor Shift", isOn: $settings.cursorShift)
        }
    }

    // MARK: - Lock

    private var lockSection: some View {
        Section("Lock") {
            Toggle("DTMF Lock", isOn: $settings.dtmfLock)
            Toggle("Mic Lock", isOn: $settings.micLock)
            Toggle("Volume Lock", isOn: $settings.volumeLock)
        }
    }

    // MARK: - Units

    private var unitsSection: some View {
        Section("Units & GPS") {
            pickerRow("Speed", selection: $settings.speedUnit,
                      options: RadioSettings.speedUnitOptions,
                      label: "Speed unit for GPS display")

            pickerRow("Altitude", selection: $settings.altitudeUnit,
                      options: RadioSettings.altUnitOptions,
                      label: "Altitude unit for GPS display")

            pickerRow("Temperature", selection: $settings.tempUnit,
                      options: RadioSettings.tempUnitOptions,
                      label: "Temperature unit")

            pickerRow("Lat/Long Format", selection: $settings.latLongUnit,
                      options: RadioSettings.latLonOptions,
                      label: "Latitude/longitude display format")

            pickerRow("Grid Square Format", selection: $settings.gridSquare,
                      options: RadioSettings.gridSquareOptions,
                      label: "Grid square display format for GPS position")
        }
    }

    // MARK: - Interface

    private var interfaceSection: some View {
        Section("Interface") {
            pickerRow("Language", selection: $settings.language,
                      options: RadioSettings.languageOptions,
                      label: "Display language")

            pickerRow("Callsign Readout", selection: $settings.callsignReadout,
                      options: RadioSettings.callsignReadoutOptions,
                      label: "How alphabetic characters in callsigns are spoken by voice guidance")

            Toggle("FM Radio", isOn: $settings.fmRadioEnabled)

            Toggle("WX Alert on FM", isOn: $settings.wxAlert)
        }
    }

    // MARK: - PC Interface

    private var pcInterfaceSection: some View {
        Section("PC Interface") {
            pickerRow("USB Function", selection: $settings.usbFunction,
                      options: RadioSettings.usbFunctionOptions,
                      label: "USB port function, COM port with AF/IF output, or mass storage for microSD")

            pickerRow("GPS Output Interface", selection: $settings.pcOutputGpsInterface,
                      options: RadioSettings.usbBtInterfaceOptions,
                      label: "GPS NMEA sentence output interface, USB or Bluetooth")

            pickerRow("APRS Output Interface", selection: $settings.pcOutputAprsInterface,
                      options: RadioSettings.usbBtInterfaceOptions,
                      label: "APRS packet output interface, USB or Bluetooth")

            pickerRow("KISS Interface", selection: $settings.kissInterface,
                      options: RadioSettings.usbBtInterfaceOptions,
                      label: "KISS TNC interface, USB or Bluetooth")

            pickerRow("DV/DR Interface", selection: $settings.dvDrInterface,
                      options: RadioSettings.usbBtInterfaceOptions,
                      label: "D-STAR DV and DR data interface, USB or Bluetooth")
        }
    }

    // MARK: - TX Power

    private var txPowerSection: some View {
        Section("TX Power") {
            pickerRow("A Band TX Power", selection: $settings.aBandTxPower,
                      options: RadioSettings.txPowerOptions,
                      label: "A band transmit power level")

            pickerRow("B Band TX Power", selection: $settings.bBandTxPower,
                      options: RadioSettings.txPowerOptions,
                      label: "B band transmit power level")
        }
    }

    // MARK: - Helpers

    private var balanceLabel: String {
        let v = Int(settings.audioBalance)
        if v < 5 { return "A +\(5 - v)" }
        if v > 5 { return "B +\(v - 5)" }
        return "Center"
    }

    @ViewBuilder
    private func pickerRow(_ title: String, selection: Binding<UInt8>,
                           options: [String], label: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(options.enumerated()), id: \.offset) { index, name in
                Text(name).tag(UInt8(index))
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(label)
    }

    @ViewBuilder
    private func pfPicker(_ title: String, selection: Binding<UInt8>, label: String) -> some View {
        Picker(title, selection: selection) {
            ForEach(Array(RadioSettings.pfKeyOptions.enumerated()), id: \.offset) { index, name in
                Text(name).tag(UInt8(index))
            }
        }
        .pickerStyle(.menu)
        .accessibilityLabel(label)
    }
}
