// RadioSettings.swift — Radio-wide settings stored in the memory blob
// Byte offsets derived from RadioInfo$RadioSpecific Java struct (Unknown* field naming convention)

import Foundation

struct RadioSettings: Equatable {

    // MARK: - Radio
    // D75 settings block shifted ~0x100 from D74. Verified offsets marked (✓).
    // Remaining unverified offsets marked (TODO) — shifted by -0x100 from D74 as best guess.
    var beatShift: Bool = false          // 0x1000  (TODO: verify, was D74 0x1100)
    var txInhibit: Bool = false          // 0x1001  (TODO: verify, was D74 0x1101)
    var timeOutTimer: UInt8 = 0          // 0x1003  ✓ Menu 111: 0=0.5min … 5=3.0min … 10=10.0min
    var barAntenna: UInt8 = 1            // 0x1005  ✓ BS / Menu 104: 0=external 1=internal
    var micSensitivity: UInt8 = 1        // 0x1006  ✓ Menu 112: 0=High 1=Med 2=Low (inverted from label!)
    var wxAlert: Bool = false            // 0x1007  (TODO: verify, Menu 105)
    var ssbHighCut: UInt8 = 0            // 0x1008  ✓ SH 0 / Menu 120: 0=2.2k 1=2.4k 2=2.6k 3=2.8k 4=3.0k
    var cwWidth: UInt8 = 0               // 0x1009  ✓ SH 1 / Menu 121: 0=0.3k 1=0.5k 2=1.0k 3=1.5k 4=2.0k
    var amHighCut: UInt8 = 0             // 0x100A  ✓ SH 2 / Menu 122: 0=3.0k 1=4.5k 2=6.0k 3=7.5k
    var autoRepeaterShift: Bool = false  // 0x1017  (TODO: verify, Menu 141)
    var callKey: UInt8 = 0               // 0x1018  (TODO: verify, Menu 142)
    var toneBurstHold: Bool = false      // 0x1019  (TODO: verify, Menu 143)

    // MARK: - Scan
    var scanResumeAnalog: UInt8 = 0      // 0x100C  ✓ Menu 130: 0=Time 1=Carrier 2=Seek
    var scanResumeDigital: UInt8 = 0     // 0x100D  (TODO: verify, Menu 131)
    var scanTimeRestart: UInt8 = 0       // 0x100E  ✓ Menu 132: value in seconds (1–10)
    var scanCarrierRestart: UInt8 = 0    // 0x100F  (TODO: verify, Menu 133)
    var priorityScan: UInt8 = 0          // 0x1011  (TODO: verify, Menu 134 — would not change on radio)
    var scanAutoBacklight: Bool = false  // 0x1012  (TODO: verify, Menu 135)
    var scanWeatherAuto: Bool = false    // 0x1013  (TODO: verify, Menu 136)

    // MARK: - VOX (reordered on D75: enabled, gain, delay instead of gain, delay, enabled)
    var voxEnabled: Bool = false         // 0x101B  ✓ VX / Menu 150
    var voxGain: UInt8 = 0               // 0x101C  ✓ VG / Menu 151: 0–9
    var voxDelay: UInt8 = 0              // 0x101D  ✓ VD / Menu 152: 0=250ms 1=500ms … 5=2000ms 6=3000ms
    var voxHysteresis: UInt8 = 0         // 0x101E  (TODO: verify, Menu 153)

    // MARK: - DTMF
    var dtmfSpeed: UInt8 = 0             // 0x101F  ✓ Menu 160: 0=50ms 1=100ms 2=150ms
    var dtmfHold: UInt8 = 0              // 0x1020  (TODO: verify, Menu 162)
    var dtmfPause: UInt8 = 0             // 0x1021  ✓ Menu 161: pause time index

    // MARK: - CW
    var cwPitch: UInt8 = 3               // 0x1024  ✓ Menu 170: 0=400Hz … 4=800Hz … 6=1000Hz
    var cwReverse: Bool = false          // 0x1025  (TODO: verify, Menu 171)
    var qsoLog: Bool = false             // 0x1026  ✓ Menu 180: 0=Off 1=On

    // MARK: - Audio Recording / Recall
    var recallMethod: UInt8 = 0          // 0x1030  (TODO: verify, Menu 202)
    var audioRecordingBand: UInt8 = 0    // 0x1031  (TODO: verify, Menu 302)
    var audioTxMonitor: Bool = false     // 0x1032  (TODO: verify, Menu 311)

    // MARK: - FM Radio
    var fmRadioEnabled: Bool = false     // 0x1040  (TODO: verify, Menu 700)
    var fmRadioAutoMute: UInt8 = 0       // 0x1041  (TODO: verify, Menu 701)

    // MARK: - Display
    var displayBacklight: UInt8 = 0      // 0x1060  ✓ LC / Menu 900: 0=Auto 1=Auto(DC-IN) 2=Manual 3=On
    var displayBacklightTimer: UInt8 = 0 // 0x1061  (TODO: verify, Menu 901)
    var displayBrightness: UInt8 = 0     // 0x1062  ✓ Menu 902: 0=Low 1=Medium 2=High (inverted from label!)
    var displaySingleBand: UInt8 = 0     // 0x1063  (TODO: verify, Menu 904)
    var displayMeterType: UInt8 = 0      // 0x1064  ✓ Menu 905: 0=Type1 1=Type2 2=Type3
    var displayBgColor: UInt8 = 0        // 0x1065  ✓ Menu 906: 0=Black 1=White

    // MARK: - Audio
    var audioBalance: UInt8 = 5          // 0x1066  (TODO: verify, Menu 910)
    var beep: Bool = true                // 0x1071  ✓ Menu 914: 0=Off 1=On
    var beepVolume: UInt8 = 0            // 0x1072  ✓ Menu 915: 0=VolLink 1=Level1 … 7=Level7
    var voiceGuidance: UInt8 = 0         // 0x1073  ✓ Menu 916: 0=Off 1=Manual 2=Auto2 3=Auto1 (note: 2/3 swapped!)
    var voiceGuidanceSpeed: UInt8 = 0    // 0x1093  (TODO: verify, Menu 918)
    var usbAudio: Bool = false           // 0x1075  (TODO: verify)

    // MARK: - Power / Bluetooth
    var batterySaver: UInt8 = 0          // 0x1076  ✓ Menu 920: 0=Off 1=0.2s … 6=2.0s … 9=5.0s
    var autoPowerOff: UInt8 = 0          // 0x1077  ✓ Menu 921: 0=Off 1=15min 2=30min 3=60min
    var btEnabled: Bool = false          // 0x1078  ✓ BT / Menu 930
    var btAutoConnect: Bool = false      // 0x1079  (TODO: verify, Menu 936)

    // MARK: - PF Keys
    var pf1Key: UInt8 = 0                // 0x107A  ✓ Menu 940
    var pf2Key: UInt8 = 0                // 0x107B  (TODO: verify, Menu 941)
    var pf1MicKey: UInt8 = 0             // 0x107C  (TODO: verify, Menu 942)
    var pf2MicKey: UInt8 = 0             // 0x107D  (TODO: verify, Menu 943)
    var pf3MicKey: UInt8 = 0             // 0x107E  (TODO: verify, Menu 944)
    var cursorShift: Bool = false        // 0x107F  (TODO: verify, Menu 945)

    // MARK: - Lock
    var keysLockType: UInt8 = 0          // 0x1086  (TODO: verify, Menu 960 — or dtmfLock?)
    var dtmfLock: Bool = false           // 0x1087  (TODO: verify, Menu 961)
    var micLock: Bool = false            // 0x1088  ✓ Menu 963 (was labeled volumeLock, confirmed as lock byte)
    var volumeLock: Bool = false         // 0x1089  (TODO: verify — may need to swap with 0x1088)

    // MARK: - Units
    var speedUnit: UInt8 = 0             // 0x108A  (TODO: verify, Menu 970)
    var altitudeUnit: UInt8 = 0          // 0x108B  (TODO: verify, Menu 971)
    var tempUnit: UInt8 = 0              // 0x108C  ✓ or latLongUnit? — 0→2 matched units change
    var latLongUnit: UInt8 = 0           // 0x108D  (TODO: verify, Menu 973)
    var gridSquare: UInt8 = 0            // 0x108E  (TODO: verify, Menu 974)

    // MARK: - Interface
    var interfaceType: UInt8 = 0         // 0x108F  (TODO: verify, Menu 980 area)
    var language: UInt8 = 0              // 0x1090  (TODO: verify, Menu 990)
    var batteryCharging: UInt8 = 0       // 0x1091  (TODO: verify, Menu 923)
    var callsignReadout: UInt8 = 0       // 0x1092  (TODO: verify, Menu 919)
    var infoBacklight: UInt8 = 0         // 0x1093  (TODO: verify, Menu 907)

    // MARK: - LED Control
    var ledControlRx: Bool = false       // 0x1095  (TODO: verify, Menu 181)
    var ledControlFmRadio: Bool = false  // 0x1096  (TODO: verify, Menu 181)

    // MARK: - Detect Out / PC Interface
    var detectOutSelect: UInt8 = 0       // 0x1002  (TODO: verify, Menu 102)
    var usbFunction: UInt8 = 0           // 0x1097  (TODO: verify, Menu 980)
    var pcOutputGpsInterface: UInt8 = 0  // 0x1098  (TODO: verify, Menu 981)
    var pcOutputAprsInterface: UInt8 = 0 // 0x1099  (TODO: verify, Menu 982)
    var kissInterface: UInt8 = 0         // 0x109A  (TODO: verify, Menu 983)
    var dvDrInterface: UInt8 = 0         // 0x109B  (TODO: verify, Menu 984)

    // MARK: - Voice Guidance Volume / USB Audio Output Level
    var voiceGuidanceVolume: UInt8 = 0   // 0x1074  (TODO: verify, Menu 917)
    var usbAudioOutputLevel: UInt8 = 0   // 0x109C  (TODO: verify, Menu 91A)

    // MARK: - Power-On Message
    var powerOnMessage: String = ""      // 0x10A0–0x10AF  (TODO: verify, Menu 903)

    // MARK: - TX Power (per-band, in VFO state area)
    var aBandTxPower: UInt8 = 0          // 0x0359  ✓ PC 0: 0=High 1=Mid 2=Low 3=EL (was D74 0x0459)
    var bBandTxPower: UInt8 = 0          // 0x0369  ✓ PC 1: 0=High 1=Mid 2=Low 3=EL (was D74 0x0469)

    // MARK: - Per-band settings (new D75 offsets, not in D74 mapping)
    var aBandSquelch: UInt8 = 0          // 0x035B  ✓ SQ 0: 0–5
    var bBandSquelch: UInt8 = 0          // 0x036B  ✓ SQ 1: 0–5
    var aBandAttenuator: Bool = false    // 0x035C  ✓ RA 0: 0=off 1=on
    var dualBandMode: UInt8 = 0          // 0x0396  ✓ DL: 0=dual 1=single
    var positionSource: UInt8 = 0        // 0x02B0  ✓ MS: 0=GPS 1-5=stored

    // MARK: - Init from raw memory blob

    init(from data: Data) {
        let base = data.startIndex
        func b(_ offset: Int) -> UInt8 {
            let idx = base + offset
            guard idx < data.endIndex else { return 0 }
            return data[idx]
        }
        func flag(_ offset: Int) -> Bool { b(offset) != 0 }
        func str(_ offset: Int, length: Int) -> String {
            let start = base + offset
            guard start < data.endIndex else { return "" }
            let end = Swift.min(start + length, data.endIndex)
            let trimmed = data[start..<end].prefix(while: { $0 != 0x00 && $0 != 0xFF })
            return String(bytes: trimmed, encoding: .ascii) ?? ""
        }

        beatShift        = flag(0x1000)
        txInhibit        = flag(0x1001)
        timeOutTimer     = b(0x1003)
        barAntenna       = b(0x1005)
        micSensitivity   = b(0x1006)
        wxAlert          = flag(0x1007)
        ssbHighCut       = b(0x1008)
        cwWidth          = b(0x1009)
        amHighCut        = b(0x100A)

        scanResumeAnalog  = b(0x100C)
        scanResumeDigital = b(0x100D)
        scanTimeRestart   = b(0x100E)
        scanCarrierRestart = b(0x100F)
        priorityScan      = b(0x1011)
        scanAutoBacklight = flag(0x1012)
        scanWeatherAuto   = flag(0x1013)

        autoRepeaterShift = flag(0x1017)
        callKey           = b(0x1018)
        toneBurstHold     = flag(0x1019)
        voxEnabled        = flag(0x101B)
        voxGain           = b(0x101C)
        voxDelay          = b(0x101D)
        voxHysteresis     = b(0x101E)
        dtmfSpeed         = b(0x101F)
        dtmfHold          = b(0x1020)
        dtmfPause         = b(0x1021)

        cwPitch    = b(0x1024)
        cwReverse  = flag(0x1025)
        qsoLog     = flag(0x1026)

        recallMethod       = b(0x1030)
        audioRecordingBand = b(0x1031)
        audioTxMonitor     = flag(0x1032)

        fmRadioEnabled  = flag(0x1040)
        fmRadioAutoMute = b(0x1041)

        displayBacklight      = b(0x1060)
        displayBacklightTimer = b(0x1061)
        displayBrightness     = b(0x1062)
        displaySingleBand     = b(0x1063)
        displayMeterType      = b(0x1064)
        displayBgColor        = b(0x1065)

        audioBalance      = b(0x1066)
        beep              = flag(0x1071)
        beepVolume        = b(0x1072)
        voiceGuidance     = b(0x1073)
        usbAudio          = flag(0x1075)

        batterySaver  = b(0x1076)
        autoPowerOff  = b(0x1077)
        btEnabled     = flag(0x1078)
        btAutoConnect = flag(0x1079)

        pf1Key      = b(0x107A)
        pf2Key      = b(0x107B)
        pf1MicKey   = b(0x107C)
        pf2MicKey   = b(0x107D)
        pf3MicKey   = b(0x107E)
        cursorShift = flag(0x107F)

        keysLockType = b(0x1086)
        dtmfLock   = flag(0x1087)
        micLock    = flag(0x1088)
        volumeLock = flag(0x1089)

        speedUnit    = b(0x108A)
        altitudeUnit = b(0x108B)
        tempUnit     = b(0x108C)
        latLongUnit  = b(0x108D)
        gridSquare   = b(0x108E)

        interfaceType    = b(0x108F)
        language         = b(0x1090)
        batteryCharging  = b(0x1091)
        callsignReadout  = b(0x1092)
        infoBacklight    = b(0x1093)
        voiceGuidanceSpeed = b(0x1094)

        ledControlRx         = flag(0x1095)
        ledControlFmRadio    = flag(0x1096)
        usbFunction          = b(0x1097)
        pcOutputGpsInterface  = b(0x1098)
        pcOutputAprsInterface = b(0x1099)
        kissInterface         = b(0x109A)
        dvDrInterface         = b(0x109B)
        usbAudioOutputLevel  = b(0x109C)
        voiceGuidanceVolume  = b(0x1074)
        detectOutSelect      = b(0x1002)
        powerOnMessage       = str(0x10A0, length: 16)

        aBandTxPower = b(0x0359)
        bBandTxPower = b(0x0369)
        aBandSquelch = b(0x035B)
        bBandSquelch = b(0x036B)
        aBandAttenuator = flag(0x035C)
        dualBandMode = b(0x0396)
        positionSource = b(0x02B0)
    }

    // MARK: - Write back to raw memory blob

    func write(to data: inout Data) {
        let base = data.startIndex
        func set(_ offset: Int, _ value: UInt8) {
            let idx = base + offset
            guard idx < data.endIndex else { return }
            data[idx] = value
        }
        func setFlag(_ offset: Int, _ value: Bool) { set(offset, value ? 1 : 0) }
        func setStr(_ offset: Int, _ value: String, length: Int) {
            var bytes = Array(value.utf8.prefix(length))
            while bytes.count < length { bytes.append(0x00) }
            for (i, byte) in bytes.enumerated() { set(offset + i, byte) }
        }

        setFlag(0x1000, beatShift)
        setFlag(0x1001, txInhibit)
        set(0x1003, timeOutTimer)
        set(0x1005, barAntenna)
        set(0x1006, micSensitivity)
        setFlag(0x1007, wxAlert)
        set(0x1008, ssbHighCut)
        set(0x1009, cwWidth)
        set(0x100A, amHighCut)

        set(0x100C, scanResumeAnalog)
        set(0x100D, scanResumeDigital)
        set(0x100E, scanTimeRestart)
        set(0x100F, scanCarrierRestart)
        set(0x1011, priorityScan)
        setFlag(0x1012, scanAutoBacklight)
        setFlag(0x1013, scanWeatherAuto)

        setFlag(0x1017, autoRepeaterShift)
        set(0x1018, callKey)
        setFlag(0x1019, toneBurstHold)
        setFlag(0x101B, voxEnabled)
        set(0x101C, voxGain)
        set(0x101D, voxDelay)
        set(0x101E, voxHysteresis)
        set(0x101F, dtmfSpeed)
        set(0x1020, dtmfHold)
        set(0x1021, dtmfPause)

        set(0x1024, cwPitch)
        setFlag(0x1025, cwReverse)
        setFlag(0x1026, qsoLog)

        set(0x1030, recallMethod)
        set(0x1031, audioRecordingBand)
        setFlag(0x1032, audioTxMonitor)

        setFlag(0x1040, fmRadioEnabled)
        set(0x1041, fmRadioAutoMute)

        set(0x1060, displayBacklight)
        set(0x1061, displayBacklightTimer)
        set(0x1062, displayBrightness)
        set(0x1063, displaySingleBand)
        set(0x1064, displayMeterType)
        set(0x1065, displayBgColor)

        set(0x1066, audioBalance)
        setFlag(0x1071, beep)
        set(0x1072, beepVolume)
        set(0x1073, voiceGuidance)
        setFlag(0x1075, usbAudio)

        set(0x1076, batterySaver)
        set(0x1077, autoPowerOff)
        setFlag(0x1078, btEnabled)
        setFlag(0x1079, btAutoConnect)

        set(0x107A, pf1Key)
        set(0x107B, pf2Key)
        set(0x107C, pf1MicKey)
        set(0x107D, pf2MicKey)
        set(0x107E, pf3MicKey)
        setFlag(0x107F, cursorShift)

        set(0x1086, keysLockType)
        setFlag(0x1087, dtmfLock)
        setFlag(0x1088, micLock)
        setFlag(0x1089, volumeLock)

        set(0x108A, speedUnit)
        set(0x108B, altitudeUnit)
        set(0x108C, tempUnit)
        set(0x108D, latLongUnit)
        set(0x108E, gridSquare)

        set(0x108F, interfaceType)
        set(0x1090, language)
        set(0x1091, batteryCharging)
        set(0x1092, callsignReadout)
        set(0x1093, infoBacklight)
        set(0x1094, voiceGuidanceSpeed)

        setFlag(0x1095, ledControlRx)
        setFlag(0x1096, ledControlFmRadio)
        set(0x1097, usbFunction)
        set(0x1098, pcOutputGpsInterface)
        set(0x1099, pcOutputAprsInterface)
        set(0x109A, kissInterface)
        set(0x109B, dvDrInterface)
        set(0x109C, usbAudioOutputLevel)
        set(0x1074, voiceGuidanceVolume)
        set(0x1002, detectOutSelect)
        setStr(0x10A0, powerOnMessage, length: 16)

        set(0x0359, aBandTxPower)
        set(0x0369, bBandTxPower)
        set(0x035B, aBandSquelch)
        set(0x036B, bBandSquelch)
        setFlag(0x035C, aBandAttenuator)
        set(0x0396, dualBandMode)
        set(0x02B0, positionSource)
    }
}

// MARK: - Option label tables

extension RadioSettings {
    static let ssbHighCutOptions     = ["2.2 kHz", "2.4 kHz", "2.6 kHz", "2.8 kHz", "3.0 kHz"]
    static let cwWidthOptions        = ["0.3 kHz", "0.5 kHz", "1.0 kHz", "1.5 kHz", "2.0 kHz"]
    static let amHighCutOptions      = ["3.0 kHz", "4.5 kHz", "6.0 kHz", "7.5 kHz"]
    static let timeOutTimerOptions   = ["0.5 min", "1.0 min", "1.5 min", "2.0 min", "2.5 min", "3.0 min", "3.5 min", "4.0 min", "4.5 min", "5.0 min", "10.0 min"]
    static let micSensOptions        = ["Low", "Medium", "High"]
    static let scanResumeOptions     = ["3 sec", "5 sec", "10 sec", "15 sec", "Busy", "Hold"]
    static let priorityScanOptions   = ["Off", "Low", "High", "Bell"]
    static let voxDelayOptions       = ["250 ms", "500 ms", "750 ms", "1000 ms", "1250 ms", "1500 ms", "1750 ms", "2000 ms"]
    static let dtmfSpeedOptions      = ["Fast (50 ms)", "Slow (100 ms)"]
    static let dtmfHoldOptions       = ["250 ms", "500 ms", "750 ms", "1000 ms"]
    static let dtmfPauseOptions      = ["250 ms", "500 ms", "750 ms", "1000 ms", "1250 ms", "1500 ms", "1750 ms", "2000 ms"]
    static let cwPitchOptions        = ["400 Hz", "500 Hz", "600 Hz", "700 Hz", "800 Hz", "900 Hz", "1000 Hz"]
    static let recallOptions         = ["Frequency", "Scan"]
    static let recordingBandOptions  = ["A Band", "B Band", "Both Bands"]
    static let backlightOptions      = ["Auto", "Auto (DC-IN)", "Manual", "On"]
    static let brightnessOptions     = ["High", "Medium", "Low"]
    static let singleBandDisplayOptions = ["Off", "GPS (Altitude)", "GPS (GS)", "Date", "Demodulation Mode"]
    static let meterTypeOptions      = ["Type 1", "Type 2", "Type 3"]
    static let bgColorOptions        = ["Black", "White"]
    static let infoBacklightOptions  = ["Off", "LCD", "LCD+Key"]
    static let beepVolumeOptions     = ["VOL Link", "Level 1", "Level 2", "Level 3", "Level 4", "Level 5", "Level 6", "Level 7"]
    static let voiceGuidanceOptions  = ["Off", "Manual", "Auto1", "Auto2"]
    static let voiceGuidanceVolumeOptions = ["VOL Link", "Level 1", "Level 2", "Level 3", "Level 4", "Level 5", "Level 6", "Level 7"]
    static let vgSpeedOptions        = ["Speed 1", "Speed 2", "Speed 3", "Speed 4"]
    static let callsignReadoutOptions = ["Standard", "Full Phonetics", "Suffix Phonetics"]
    static let batterySaverOptions   = ["Off", "0.2 sec", "0.4 sec", "0.6 sec", "0.8 sec", "1.0 sec", "2.0 sec", "3.0 sec", "4.0 sec", "5.0 sec"]
    static let autoPowerOffOptions   = ["Off", "15 min", "30 min", "60 min"]
    static let txPowerOptions        = ["High", "Medium", "Low", "EL (Extra Low)"]
    static let speedUnitOptions      = ["km/h", "mph", "knots"]
    static let altUnitOptions        = ["Meters", "Feet"]
    static let tempUnitOptions       = ["Celsius (°C)", "Fahrenheit (°F)"]
    static let latLonOptions         = ["ddd.dddd", "ddd mm.mm", "ddd mm ss"]
    static let gridSquareOptions     = ["Maidenhead Grid", "SAR Grid (CONV)", "SAR Grid (CELL)"]
    static let languageOptions       = ["English", "Japanese"]
    static let battChargingOptions   = ["Off", "On"]
    static let pfKeyOptions          = [
        "Off", "Band Select", "Monitor", "Low Power", "Lock",
        "Scan", "T-CALL", "DG-ID", "VGS", "WX", "APRS", "Message"
    ]
    static let detectOutOptions      = ["AF Output", "IF Output", "Detect Output"]
    static let usbFunctionOptions    = ["COM + AF/IF Output", "Mass Storage"]
    static let usbBtInterfaceOptions = ["USB", "Bluetooth"]
    static let usbAudioOutputLevelOptions = ["Level 1", "Level 2", "Level 3", "Level 4", "Level 5", "Level 6", "Level 7"]
}

// MARK: - MemoryMap integration

extension MemoryMap {
    func radioSettings() -> RadioSettings {
        RadioSettings(from: raw)
    }

    func setRadioSettings(_ settings: RadioSettings) {
        settings.write(to: &raw)
    }
}

// MARK: - APRS Settings

struct APRSSettings: Equatable {

    // MARK: - Basic Settings (Menus 500–509)
    var myCallsign: String = ""          // up to 6 chars  @ 0x1200  (confirmed) Menu 500
    var mySSID: UInt8 = 0                // 0–15           @ 0x1200  (confirmed, derived from callsign field "-N" suffix) Menu 500
    var symbolTable: UInt8 = 0           // 0='/' 1='\'    @ 0x1367  (confirmed) Menu 501
    var symbolCode: UInt8 = 0x3E         // APRS symbol    @ 0x1368  (confirmed) Menu 501
    var positionComment: UInt8 = 0       // 0=OffDuty 1=Enroute 2=InService 3=Returning 4=Committed 5=Special 6=PRIORITY 7=EMERGENCY  @ 0x1222  (confirmed) Menu 501
    // Status texts 1–5 with individual TX rates (Menu 503)
    var statusText1: String = ""         // up to 45 chars @ 0x1230  (confirmed)
    var statusTxRate1: UInt8 = 0         // 0=Off 1=1/1 2=1/2 3=1/4 4=1/8  @ 0x125D
    var statusText2: String = ""         // up to 45 chars @ 0x1260  (confirmed)
    var statusTxRate2: UInt8 = 0         //                @ 0x128D
    var statusText3: String = ""         //                @ 0x1290  (confirmed)
    var statusTxRate3: UInt8 = 0         //                @ 0x12BD
    var statusText4: String = ""         //                @ 0x12C0  (confirmed)
    var statusTxRate4: UInt8 = 0         //                @ 0x12ED
    var statusText5: String = ""         //                @ 0x1300  (confirmed; after 16-byte gap)
    var statusTxRate5: UInt8 = 0         //                @ 0x132D
    var statusTextMessageSelected: UInt8 = 0  // 0–4, which status text is active  @ 0x122F
    // Packet path (Menu 504)
    var pathType: UInt8 = 0              // 0=New-N 1=Relay 2=Region 3=Others1 4=Others2 5=Others3  @ 0x1375  (confirmed)
    var pathWide1_1: Bool = true         // WIDE1-1 On/Off  @ 0x1376  (confirmed)
    var pathRelay: Bool = false          // RELAY On/Off    @ TODO: verify
    var pathAbbr: String = ""            // up to 5 chars   @ TODO: verify
    var pathTotalHops: UInt8 = 1         // 0–7             @ 0x1377  (confirmed)
    var pathCustom: String = ""          // up to 79 chars  @ TODO: verify
    // Data settings (Menus 505–509)
    var dataSpeed: UInt8 = 0             // 0=1200bps 1=9600bps              @ 0x120C  (confirmed) Menu 505
    var dataBand: UInt8 = 0              // 0=ABand 1=BBand                  @ 0x120B  (confirmed) Menu 506
    var dcdSense: UInt8 = 0              // 0=Busy 1=DetectData 2=Off        @ 0x120D  (confirmed) Menu 507
    var txDelay: UInt8 = 2               // 0=100ms 1=150ms 2=200ms 3=300ms 4=400ms 5=500ms 6=750ms 7=1000ms  @ 0x120F  (confirmed) Menu 508
    var aprsLockFreq: Bool = false       // Lock frequency  @ 0x120A bit 0  (confirmed) Menu 509
    var aprsLockPTT: Bool = false        // Lock PTT        @ 0x120A bit 1  (confirmed) Menu 509
    var aprsLockKey: Bool = false        // Lock APRS key   @ 0x120A bit 2  (confirmed) Menu 509

    // MARK: - Beacon TX Control (Menus 510–516)
    var beaconMode: UInt8 = 0            // 0=Manual 1=PTT 2=Auto 3=SmartBeaconing  @ 0x136A  (confirmed) Menu 510
    var beaconInterval: UInt8 = 1        // 0=0.2min 1=0.5min 2=1min … 9=30min 10=60min  @ 0x136B  (confirmed) Menu 511
    var decayAlgorithm: Bool = false     // On/Off                           @ 0x136C  (confirmed) Menu 512
    var propPathing: Bool = false        // On/Off                           @ 0x136D  (confirmed) Menu 513
    var beaconIncludeSpeed: Bool = false // include speed in beacon          @ 0x1220  (confirmed) Menu 514
    var beaconIncludeAlt: Bool = false   // include altitude in beacon       @ 0x1221  (confirmed) Menu 515

    // MARK: - QSY Information (Menus 520–523)
    var qsyInfoInStatus: Bool = false    // On/Off                           @ 0x0660  (TODO: verify) Menu 520
    var qsyToneNarrow: Bool = false      // On/Off                           @ 0x0661  (TODO: verify) Menu 521
    var qsyShiftOffset: Bool = false     // On/Off                           @ 0x0662  (TODO: verify) Menu 522
    var qsyLimitDistance: UInt8 = 0      // 0=Off 1=10 2=20 … (miles/km/nm) @ 0x0663  (TODO: verify) Menu 523

    // MARK: - SmartBeaconing (Menus 530–535)
    var smartBeaconingLow: UInt8 = 5     // 2–30 mph/km/knots                @ 0x136E  (confirmed)
    var smartBeaconingHigh: UInt8 = 70   // 2–90 mph/km/knots                @ 0x136F  (confirmed)
    var smartBeaconingSlowRate: UInt8 = 30  // 1–100 min                     @ 0x1370  (confirmed)
    var smartBeaconingFastRate: UInt8 = 120 // 10–180 sec                    @ 0x1371  (confirmed)
    var smartBeaconingTurnAngle: UInt8 = 28  // 5–90 deg                     @ 0x1372  (confirmed)
    var smartBeaconingTurnSlope: UInt8 = 26  // 1–255 (10deg/speed)          @ 0x1373  (confirmed)
    var smartBeaconingTurnTime: UInt8 = 60   // 5–180 sec                    @ 0x1374  (confirmed)

    // MARK: - Waypoint (Menus 540–542)
    var waypointFormat: UInt8 = 0        // 0=NMEA 1=MAGELLAN 2=KENWOOD      @ 0x0680  (TODO: verify) Menu 540
    var waypointLength: UInt8 = 0        // 0=6-Char 1=7-Char 2=8-Char 3=9-Char  @ 0x0681  (TODO: verify) Menu 541
    var waypointOutput: UInt8 = 0        // 0=All 1=Local 2=Filtered         @ 0x0682  (TODO: verify) Menu 542

    // MARK: - Packet Filter (Menus 550–551)
    var positionLimit: UInt8 = 0         // 0=Off 1=10 2=20 … (miles/km/nm) @ 0x0690  (TODO: verify) Menu 550
    var filterType: UInt8 = 0            // bitmask: Weather/Digipeater/Mobile/Object/NAVITRA/1-WAY/Others  @ 0x0691  (TODO: verify) Menu 551

    // MARK: - Message (Menus 560–564)
    var autoReply: Bool = false          // On/Off                           @ 0x06A0  (TODO: verify) Menu 561
    var replyTo: String = ""             // up to 9 chars                    @ 0x06A1  (TODO: verify) Menu 562
    var replyDelay: UInt8 = 0            // 0=0s 1=10s 2=20s 3=30s 4=60s    @ 0x06AA  (TODO: verify) Menu 563
    var replyMessage: String = ""        // up to 50 chars                   @ 0x06AB  (TODO: verify) Menu 564

    // MARK: - Notification (Menus 570–575)
    var rxBeep: UInt8 = 0                // 0=Off 1=MessageOnly 2=Mine 3=AllNew 4=All  @ 0x06C0  (TODO: verify) Menu 570
    var txBeep: Bool = false             // On/Off                           @ 0x06C1  (TODO: verify) Menu 571
    var specialCall: String = ""         // up to 9 chars                    @ 0x06C2  (TODO: verify) Menu 572
    var displayArea: UInt8 = 0           // 0=EntireAlways 1=EntireDisplay 2=OneLine  @ 0x06CB  (TODO: verify) Menu 573
    var interruptTime: UInt8 = 1         // 0=3s 1=5s 2=10s 3=20s 4=30s 5=60s 6=Infinite  @ 0x06CC  (TODO: verify) Menu 574
    var aprsVoice: Bool = false          // On/Off                           @ 0x06CD  (TODO: verify) Menu 575

    // MARK: - Digipeat (Menus 580–588)
    var digipeatMyCall: Bool = false     // On/Off                           @ 0x06D0  (TODO: verify) Menu 580
    var uiCheckTime: UInt8 = 28          // 1–250 sec                        @ 0x06D1  (TODO: verify) Menu 581
    var uiDigipeat: Bool = false         // On/Off                           @ 0x06D2  (TODO: verify) Menu 582
    var uiDigiAliases: String = ""       // up to 9 chars × 4                @ 0x06D3  (TODO: verify) Menu 583
    var uiFlood: Bool = false            // On/Off                           @ 0x06D4  (TODO: verify) Menu 584
    var uiFloodAlias: String = ""        // up to 5 chars                    @ 0x06D5  (TODO: verify) Menu 585
    var uiFloodSubstitution: UInt8 = 0   // 0=First 1=ID 2=NOID              @ 0x06D6  (TODO: verify) Menu 586
    var uiTrace: Bool = false            // On/Off                           @ 0x06D7  (TODO: verify) Menu 587
    var uiTraceAlias: String = ""        // up to 5 chars                    @ 0x06D8  (TODO: verify) Menu 588

    // MARK: - Others (Menus 590–595)
    var pcOutput: UInt8 = 0              // 0=Off 1=On (sentence type)       @ 0x06E0  (TODO: verify) Menu 590
    var network: UInt8 = 0              //                                   @ 0x06E1  (TODO: verify) Menu 591
    var voiceAlert: Bool = false         // On/Off                           @ 0x06E2  (TODO: verify) Menu 592
    var vaFrequency: UInt8 = 0           //                                   @ 0x06E3  (TODO: verify) Menu 593
    var messageGroupCode: String = ""    // up to 9 chars                    @ 0x06E4  (TODO: verify) Menu 594
    var bulletinGroupCode: String = ""   // up to 9 chars                    @ 0x06ED  (TODO: verify) Menu 595

    init(from data: Data) {
        let base = data.startIndex
        func b(_ offset: Int) -> UInt8 {
            let idx = base + offset
            guard idx < data.endIndex else { return 0 }
            return data[idx]
        }
        func flag(_ offset: Int) -> Bool { b(offset) != 0 }
        func str(_ offset: Int, length: Int) -> String {
            let start = base + offset
            guard start < data.endIndex else { return "" }
            let end = Swift.min(start + length, data.endIndex)
            let trimmed = data[start..<end].prefix(while: { $0 != 0x00 && $0 != 0xFF })
            return String(bytes: trimmed, encoding: .ascii) ?? ""
        }

        // 0x1200–0x1208: MY CALLSIGN+SSID (9 bytes, confirmed)
        // Format: callsign null-terminated (up to 6 bytes), then optional "-N" SSID suffix
        let csStart = base + 0x1200
        if csStart < data.endIndex {
            let csSlice = data[csStart..<Swift.min(csStart + 9, data.endIndex)]
            if let nullIdx = csSlice.firstIndex(of: 0x00) {
                myCallsign = String(bytes: csSlice[csSlice.startIndex..<nullIdx], encoding: .ascii) ?? ""
                let afterNull = csSlice.index(after: nullIdx)
                if afterNull < csSlice.endIndex && csSlice[afterNull] == UInt8(ascii: "-") {
                    let ssidStart = csSlice.index(after: afterNull)
                    let ssidBytes = csSlice[ssidStart...].prefix(while: { $0 != 0x00 && $0 != 0xFF })
                    mySSID = UInt8(String(bytes: ssidBytes, encoding: .ascii) ?? "0") ?? 0
                } else {
                    mySSID = 0
                }
            } else {
                let raw = csSlice.prefix(while: { $0 != 0xFF })
                myCallsign = String(bytes: raw, encoding: .ascii) ?? ""
                mySSID = 0
            }
        }

        // 0x120A: APRSLock bitfield — bit0=Frequency, bit1=PTT, bit2=APRSKey (confirmed)
        let lockByte = b(0x120A)
        aprsLockFreq = (lockByte & 0x01) != 0
        aprsLockPTT  = (lockByte & 0x02) != 0
        aprsLockKey  = (lockByte & 0x04) != 0

        // 0x120B: DataBand  0=ABand 1=BBand  (confirmed)
        // 0x120C: DataSpeed  0=1200bps 1=9600bps  (confirmed)
        // 0x120D: DCDSense  0=Busy 1=DetectData 2=Off  (confirmed)
        // 0x120F: TxDelay  0=100ms…7=1000ms  (confirmed)
        dataBand  = b(0x120B)
        dataSpeed = b(0x120C)
        dcdSense  = b(0x120D)
        txDelay   = b(0x120F)

        // 0x1220: BeaconInformationSpeed  (confirmed)
        // 0x1221: BeaconInformationAltitude  (confirmed)
        // 0x1222: PositionComment index  (confirmed)
        // 0x122F: StatusTextMessageSelected  (confirmed)
        beaconIncludeSpeed        = flag(0x1220)
        beaconIncludeAlt          = flag(0x1221)
        positionComment           = b(0x1222)
        statusTextMessageSelected = b(0x122F)

        // Status texts: 5 × STATUSTXTMESSAGE structs, each 48 bytes
        //   text at byte 0 (45 chars, null-terminated), txRate at byte 45
        // 0x1230–0x125F: StatusText[0]  (confirmed)
        // 0x1260–0x128F: StatusText[1]  (confirmed)
        // 0x1290–0x12BF: StatusText[2]  (confirmed)
        // 0x12C0–0x12EF: StatusText[3]  (confirmed)
        // 0x12F0–0x12FF: Unknown13F0[16] padding — skipped
        // 0x1300–0x132F: StatusTextMessage5  (confirmed)
        statusText1  = str(0x1230, length: 45); statusTxRate1 = b(0x1230 + 45)
        statusText2  = str(0x1260, length: 45); statusTxRate2 = b(0x1260 + 45)
        statusText3  = str(0x1290, length: 45); statusTxRate3 = b(0x1290 + 45)
        statusText4  = str(0x12C0, length: 45); statusTxRate4 = b(0x12C0 + 45)
        statusText5  = str(0x1300, length: 45); statusTxRate5 = b(0x1300 + 45)

        // 0x1367: Symbol table byte ('/' = primary, '\' = secondary)  (confirmed)
        // 0x1368: Symbol code byte  (confirmed)
        let tblByte = b(0x1367)
        symbolTable = (tblByte == UInt8(ascii: "\\")) ? 1 : 0
        symbolCode  = b(0x1368)

        // 0x136A: BeaconMethod (beaconMode)  (confirmed)
        // 0x136B: BeaconInitialInterval  (confirmed)
        // 0x136C: BeaconDelayAlgorithm  (confirmed)
        // 0x136D: BeaconProportionalPathing  (confirmed)
        beaconMode     = b(0x136A)
        beaconInterval = b(0x136B)
        decayAlgorithm = flag(0x136C)
        propPathing    = flag(0x136D)

        // 0x136E: SmartBeacon_LowSpeed  (confirmed)
        // 0x136F: SmartBeacon_HighSpeed  (confirmed)
        // 0x1370: SmartBeacon_SlowRate  (confirmed)
        // 0x1371: SmartBeacon_FastRate  (confirmed)
        // 0x1372: SmartBeacon_TurnAngle  (confirmed)
        // 0x1373: SmartBeacon_TurnSlope  (confirmed)
        // 0x1374: SmartBeacon_TurnTime  (confirmed)
        smartBeaconingLow       = b(0x136E)
        smartBeaconingHigh      = b(0x136F)
        smartBeaconingSlowRate  = b(0x1370)
        smartBeaconingFastRate  = b(0x1371)
        smartBeaconingTurnAngle = b(0x1372)
        smartBeaconingTurnSlope = b(0x1373)
        smartBeaconingTurnTime  = b(0x1374)

        // 0x1375: PacketPathType  (confirmed)
        // 0x1376: NewN_Wide1  (confirmed)
        // 0x1377: NewN_TotalHops  (confirmed)
        pathType      = b(0x1375)
        pathWide1_1   = flag(0x1376)
        pathTotalHops = b(0x1377)
    }

    func write(to data: inout Data) {
        let base = data.startIndex
        func set(_ offset: Int, _ value: UInt8) {
            let idx = base + offset
            guard idx < data.endIndex else { return }
            data[idx] = value
        }
        func setFlag(_ offset: Int, _ value: Bool) { set(offset, value ? 1 : 0) }
        func setStr(_ offset: Int, _ value: String, length: Int) {
            let bytes = Array(value.utf8.prefix(length))
            for (i, byte) in bytes.enumerated() { set(offset + i, byte) }
            for i in bytes.count..<length { set(offset + i, 0x00) }
        }

        // 0x1200–0x1208: MY CALLSIGN+SSID (9 bytes, confirmed)
        for i in 0..<9 { set(0x1200 + i, 0x00) }
        let csBytes = Array(myCallsign.utf8.prefix(6))
        for (i, byte) in csBytes.enumerated() { set(0x1200 + i, byte) }
        if mySSID > 0 {
            let ssidFieldStart = 0x1200 + csBytes.count + 1
            for (i, byte) in "-\(mySSID)".utf8.prefix(3).enumerated() {
                if ssidFieldStart + i < 0x1200 + 9 { set(ssidFieldStart + i, byte) }
            }
        }

        // 0x120A: APRSLock bitfield
        let lockByte: UInt8 = (aprsLockFreq ? 0x01 : 0) | (aprsLockPTT ? 0x02 : 0) | (aprsLockKey ? 0x04 : 0)
        set(0x120A, lockByte)

        set(0x120B, dataBand)
        set(0x120C, dataSpeed)
        set(0x120D, dcdSense)
        set(0x120F, txDelay)

        setFlag(0x1220, beaconIncludeSpeed)
        setFlag(0x1221, beaconIncludeAlt)
        set(0x1222, positionComment)
        set(0x122F, statusTextMessageSelected)

        // Status texts: 5 × 48-byte STATUSTXTMESSAGE structs (text 45 bytes + txRate 1 byte + 2 padding)
        setStr(0x1230, statusText1, length: 45); set(0x1230 + 45, statusTxRate1)
        setStr(0x1260, statusText2, length: 45); set(0x1260 + 45, statusTxRate2)
        setStr(0x1290, statusText3, length: 45); set(0x1290 + 45, statusTxRate3)
        setStr(0x12C0, statusText4, length: 45); set(0x12C0 + 45, statusTxRate4)
        setStr(0x1300, statusText5, length: 45); set(0x1300 + 45, statusTxRate5)

        // Symbol
        set(0x1367, symbolTable == 1 ? 0x5C : 0x2F)  // '\' or '/'
        set(0x1368, symbolCode)

        // Beacon
        set(0x136A, beaconMode)
        set(0x136B, beaconInterval)
        setFlag(0x136C, decayAlgorithm)
        setFlag(0x136D, propPathing)

        // SmartBeaconing
        set(0x136E, smartBeaconingLow)
        set(0x136F, smartBeaconingHigh)
        set(0x1370, smartBeaconingSlowRate)
        set(0x1371, smartBeaconingFastRate)
        set(0x1372, smartBeaconingTurnAngle)
        set(0x1373, smartBeaconingTurnSlope)
        set(0x1374, smartBeaconingTurnTime)

        // Path
        set(0x1375, pathType)
        setFlag(0x1376, pathWide1_1)
        set(0x1377, pathTotalHops)
    }
}

extension APRSSettings {
    // Beacon mode encoding confirmed by memory diff:
    // 0x00=PTT  0x01=Manual  0x02=Auto  0x03=SmartBeaconing
    static let beaconModeOptions      = ["PTT", "Manual", "Auto", "SmartBeaconing"]
    static let beaconIntervalOptions  = ["0.2 min", "0.5 min", "1 min", "2 min", "3 min", "5 min", "10 min", "20 min", "30 min", "60 min"]
    static let pathTypeOptions        = ["New-N", "Relay", "Region", "Others1", "Others2", "Others3"]
    static let dataSpeedOptions       = ["1200 bps", "9600 bps"]
    static let dataBandOptions        = ["A Band", "B Band"]
    static let dcdSenseOptions        = ["Busy", "Detect Data", "Off (Ignore)"]
    static let txDelayOptions         = ["100 ms", "150 ms", "200 ms", "300 ms", "400 ms", "500 ms", "750 ms", "1000 ms"]
    static let statusTxRateOptions    = ["Off", "1/1", "1/2", "1/4", "1/8"]
    static let positionCommentOptions = ["Off Duty", "Enroute", "In Service", "Returning", "Committed", "Special", "PRIORITY", "EMERGENCY!"]
    static let waypointFormatOptions  = ["NMEA", "MAGELLAN", "KENWOOD"]
    static let waypointLengthOptions  = ["6 Char", "7 Char", "8 Char", "9 Char"]
    static let waypointOutputOptions  = ["All", "Local", "Filtered"]
    static let rxBeepOptions          = ["Off", "Message Only", "Mine", "All New", "All"]
    static let displayAreaOptions     = ["Entire Always", "Entire Display", "One Line"]
    static let interruptTimeOptions   = ["3 sec", "5 sec", "10 sec", "20 sec", "30 sec", "60 sec", "Infinite"]
    static let uiFloodSubOptions      = ["First", "ID", "NOID"]
    static let replyDelayOptions      = ["0 sec", "10 sec", "20 sec", "30 sec", "60 sec"]
    static let ssidOptions            = (0...15).map { $0 == 0 ? "None (SSID-0)" : "SSID-\($0)" }
}

extension MemoryMap {
    func aprsSettings() -> APRSSettings { APRSSettings(from: raw) }
    func setAPRSSettings(_ s: APRSSettings) { s.write(to: &raw) }
}

// MARK: - D-STAR Settings

struct DSTARSettings: Equatable {

    // MARK: - My Station
    // Offsets confirmed via binary diff of Java TH-D75 Programmer memory images.
    // clone_offset = java_struct_offset − 0x100 (256-byte .d75 file header).
    var myCallsign: String = ""          // 8 bytes @ 0x1FC48  space-padded (e.g. "AI5OS   ")
    var myCallsignSuffix: String = ""    // 4 bytes @ 0x02B9  (confirmed via wizard)

    // MARK: - TX Messages (Menu 611 — up to 5 × 20-char messages)
    var txMessage1: String = ""          // 20 bytes @ 0x1A61  (confirmed via wizard)
    var txMessage2: String = ""          // 20 bytes @ 0x1A75  (struct-derived: sequential +20)
    var txMessage3: String = ""          // 20 bytes @ 0x1A89  (struct-derived: sequential +20)
    var txMessage4: String = ""          // 20 bytes @ 0x1A9D  (struct-derived: sequential +20)
    var txMessage5: String = ""          // 20 bytes @ 0x1AB1  (struct-derived: sequential +20)

    // MARK: - Repeater Routing
    // aBand confirmed via binary diff. bBand: struct-derived offsets (0x1FC70/0x1FC78) are WRONG —
    // nothing changed there. Wizard located bBand routing in the 0x006xx area instead.
    var aBandUrCall: String = ""         // 8 bytes @ 0x1FC50  (confirmed)  default "CQCQCQ  "
    var aBandRPT1: String = ""           // 8 bytes @ 0x1FC58  (confirmed)  e.g. "W5KA   C"
    var aBandRPT2: String = ""           // 8 bytes @ 0x1FC60  (confirmed)  e.g. "W5KA   G"
    var bBandRPT1: String = ""           // 8 bytes @ 0x00337  (confirmed — '/'+callsign+module, e.g. "/W5KA  C"; module at byte 8 = 0x0033E; CQCQCQ\\0\\0 = DIRECT)
    var bBandRPT2: String = ""           // 8 bytes @ 0x00337  (confirmed — shared address with bBandRPT1; control byte 0x00336 selects active routing; no '/' prefix when set directly)

    // MARK: - GPS Data TX (Menus 630–632)
    var gpsDataTxMode: Bool = false      // 0=Off 1=On            @ 0x06B7  (confirmed via wizard)
    var gpsSentence: UInt8 = 0           // 0=GGA 1=GLL 2=GSA 3=GSV 4=RMC 5=VTG 6=APRS  @ 0x1A0B  (confirmed via wizard)
    var gpsAutoTx: UInt8 = 0             // 0=Off 1=0.2min … 10=60min  @ 0x1A0C  (confirmed via wizard)

    // MARK: - RX Break-In Display (Menus 640–643)
    // All four offsets confirmed via wizard — the whole block sits 3 bytes later than
    // the struct-derived guess (0x1A0A–0x1A0D → actual 0x1A0D–0x1A10).
    var rxBreakInDisplay: UInt8 = 0      // 0=Off 1=All 2=RelatedToDSQ 3=MyStationOnly  @ 0x1A0D  (confirmed via wizard)
    var rxBreakInSizeSingle: UInt8 = 0   // 0=Half 1=Entire  @ 0x1A0E  (confirmed via wizard)
    var rxBreakInSizeDual: UInt8 = 0     // 0=Half 1=Entire  @ 0x1A0F  (confirmed via wizard)
    var rxBreakInHoldTime: UInt8 = 0     // 0=0s 1=3s 2=5s 3=10s 4=20s 5=30s 6=60s 7=Inf  @ 0x1A10  (confirmed via wizard)

    // MARK: - Callsign Announce / Standby Beep (Menus 644, 645)
    var callsignAnnounce: UInt8 = 0      // 0=Off 1=Kerchunk 2=ExceptKerchunk 3=MyStationOnly 4=All  @ 0x1A11  (confirmed via wizard)
    var standbyBeep: Bool = false        // 0=Off 1=On  @ 0x1A12  (confirmed via wizard)

    // MARK: - DV Options
    // NOTE: breakCall (Menu 619) is NOT stored — manual states "canceled when power is switched OFF".
    var autoReply: UInt8 = 0             // 0=Off 1=On 2=On(Voice)  @ 0x1A20  (confirmed via wizard)

    // MARK: - DV Menu Options (Menus 612–621)
    // TXRX_ fields confirmed via Java bytecode (TXRX struct starts at clone 0x1A00)
    var directReply: Bool = false        // Menu 612  @ 0x1A00  (confirmed)  TXRX_DirectReply
    var autoReplyTiming: UInt8 = 0       // Menu 613  0=Immediate 1=5s … 5=60s  @ 0x1A01  (confirmed)
    var dataTxEndTiming: UInt8 = 0       // Menu 614  0=Off 1=0.5s … 4=2s       @ 0x1A02  (confirmed)
    var emrVolume: UInt8 = 1             // Menu 615  1–50                       @ 0x1A03  (confirmed)
    var rxAFC: Bool = false              // Menu 616  @ 0x1A04  (confirmed)
    var fmAutoDetOnDV: Bool = false      // Menu 617  @ 0x1A05  (confirmed)
    var dataFrameOutput: UInt8 = 0       // Menu 618  0=All 1=RelatedToDSQ 2=DATAMode  @ 0x1A06  (confirmed)
    var digitalSquelchType: UInt8 = 0    // Menu 620  0=Off 1=CallsignSQ 2=CodeSQ  @ 0x030E  (confirmed via wizard; raw: Off=0x98 CallsignSQ=0x9A, packed in bits 2:1 of byte)
    var digitalCode: UInt8 = 0           // Menu 621  0=Off 1–5                       @ 0x0327  (confirmed via wizard)

    // MARK: - DV Gateway (Menus 650–653, 985)
    var dvGatewayMode: UInt8 = 0         // 0=Off 1=ReflectorTERMMode  @ TODO: verify
    var dvGatewayCallsign: String = ""   // 8 bytes @ TODO: verify  Menu 651
    var dvGatewayRPT1: String = ""       // 8 bytes @ TODO: verify  Menu 652
    var dvGatewayRPT2: String = ""       // 8 bytes @ TODO: verify  Menu 653
    var dvGatewayInterface: UInt8 = 0    // 0=USB 1=Bluetooth  @ TODO: verify  Menu 985

    init(from data: Data) {
        let base = data.startIndex
        func b(_ offset: Int) -> UInt8 {
            let idx = base + offset
            guard idx < data.endIndex else { return 0 }
            return data[idx]
        }
        // D-STAR callsigns are space-padded 8-byte ASCII fields (not null-terminated)
        func dstar(_ offset: Int, length: Int = 8) -> String {
            let start = base + offset
            guard start < data.endIndex else { return "" }
            let end = Swift.min(start + length, data.endIndex)
            let raw = data[start..<end].prefix(while: { $0 != 0x00 && $0 != 0xFF })
            return (String(bytes: raw, encoding: .ascii) ?? "").trimmingCharacters(in: .whitespaces)
        }

        // Callsign block (confirmed via binary diff)
        myCallsign  = dstar(0x1FC48)
        aBandUrCall = dstar(0x1FC50)
        aBandRPT1   = dstar(0x1FC58)
        aBandRPT2   = dstar(0x1FC60)

        // B-band repeater routing (struct-derived: sequential 8-byte blocks after A-band)
        bBandRPT1 = dstar(0x00337)   // confirmed; format: '/'+callsign+module (e.g. "/W5KA  C")
        bBandRPT2 = dstar(0x0337)    // confirmed @ 0x0337 (shared address with bBandRPT1; control byte 0x00336)

        // MY callsign suffix (confirmed via wizard @ 0x02B9, 4 bytes)
        myCallsignSuffix = dstar(0x02B9, length: 4)

        // TX messages (message 1 confirmed @ 0x1A61; messages 2–5 struct-derived +20 each)
        txMessage1 = dstar(0x1A61, length: 20)
        txMessage2 = dstar(0x1A75, length: 20)
        txMessage3 = dstar(0x1A89, length: 20)
        txMessage4 = dstar(0x1A9D, length: 20)
        txMessage5 = dstar(0x1AB1, length: 20)

        // DV TXRX options (confirmed via Java bytecode, TXRX struct base = clone 0x1A00)
        directReply     = b(0x1A00) != 0
        autoReplyTiming = b(0x1A01)
        dataTxEndTiming = b(0x1A02)
        emrVolume       = max(1, b(0x1A03))   // valid range 1–50
        rxAFC           = b(0x1A04) != 0
        fmAutoDetOnDV   = b(0x1A05) != 0
        dataFrameOutput = b(0x1A06)

        // RX break-in display (confirmed via wizard — whole block was +3 from struct-derived guess)
        rxBreakInDisplay    = b(0x1A0D)
        rxBreakInSizeSingle = b(0x1A0E)
        rxBreakInSizeDual   = b(0x1A0F)
        rxBreakInHoldTime   = b(0x1A10)

        // GPS Data TX (Menus 630–632; confirmed via wizard)
        gpsDataTxMode = b(0x06B7) != 0
        gpsSentence   = b(0x1A0B)   // confirmed via wizard
        gpsAutoTx     = b(0x1A0C)   // confirmed via wizard

        // Callsign announce + standby beep (confirmed via wizard @ 0x1A11/0x1A12)
        callsignAnnounce = b(0x1A11)
        standbyBeep      = b(0x1A12) != 0

        // Auto reply: 0=Off 1=On 2=On(Voice)  (confirmed via wizard @ 0x1A20)
        // NOTE: breakCall (Menu 619) is NOT read — it's a transient runtime flag (cleared on power off).
        autoReply = b(0x1A20)

        // Menu 620–621 (digitalSquelchType confirmed @ 0x030E; raw Off=0x98 CallsignSQ=0x9A CodeSQ=0x9C)
        digitalSquelchType = (b(0x030E) & 0x06) >> 1   // bits 2:1 encode type; base nibble 0x98 is fixed
        digitalCode        = b(0x0327)   // confirmed via wizard
    }

    func write(to data: inout Data) {
        let base = data.startIndex
        func set(_ offset: Int, _ value: UInt8) {
            let idx = base + offset
            guard idx < data.endIndex else { return }
            data[idx] = value
        }
        func setDstar(_ offset: Int, _ value: String, length: Int = 8) {
            var bytes = Array(value.utf8.prefix(length))
            while bytes.count < length { bytes.append(UInt8(ascii: " ")) }
            for (i, byte) in bytes.enumerated() { set(offset + i, byte) }
        }

        // Callsign block
        setDstar(0x1FC48, myCallsign)
        setDstar(0x1FC50, aBandUrCall)
        setDstar(0x1FC58, aBandRPT1)
        setDstar(0x1FC60, aBandRPT2)
        setDstar(0x00337, bBandRPT1)   // confirmed; writes '/'+callsign+module format
        setDstar(0x0337, bBandRPT2)    // confirmed @ 0x0337 (shared address with bBandRPT1)

        // MY callsign suffix (confirmed @ 0x02B9)
        setDstar(0x02B9, myCallsignSuffix, length: 4)

        // TX messages (message 1 confirmed; 2–5 struct-derived)
        setDstar(0x1A61, txMessage1, length: 20)
        setDstar(0x1A75, txMessage2, length: 20)
        setDstar(0x1A89, txMessage3, length: 20)
        setDstar(0x1A9D, txMessage4, length: 20)
        setDstar(0x1AB1, txMessage5, length: 20)

        // DV TXRX options
        set(0x1A00, directReply     ? 1 : 0)
        set(0x1A01, autoReplyTiming)
        set(0x1A02, dataTxEndTiming)
        set(0x1A03, emrVolume)
        set(0x1A04, rxAFC           ? 1 : 0)
        set(0x1A05, fmAutoDetOnDV   ? 1 : 0)
        set(0x1A06, dataFrameOutput)

        // RX break-in display (confirmed via wizard)
        set(0x1A0D, rxBreakInDisplay)
        set(0x1A0E, rxBreakInSizeSingle)
        set(0x1A0F, rxBreakInSizeDual)
        set(0x1A10, rxBreakInHoldTime)

        // GPS Data TX
        set(0x06B7, gpsDataTxMode ? 1 : 0)
        set(0x1A0B, gpsSentence)
        set(0x1A0C, gpsAutoTx)

        // Callsign announce + standby beep (confirmed @ 0x1A11/0x1A12)
        set(0x1A11, callsignAnnounce)
        set(0x1A12, standbyBeep ? 1 : 0)

        // Auto reply (confirmed @ 0x1A20)
        set(0x1A20, autoReply)

        // Menu 620–621 (breakCall removed — transient, not stored in file)
        set(0x030E, 0x98 | (digitalSquelchType << 1))   // confirmed @ 0x030E; base 0x98, type in bits 2:1
        set(0x0327, digitalCode)   // confirmed via wizard
    }
}

extension DSTARSettings {
    static let gpsSentenceOptions       = ["$GPGGA", "$GPGLL", "$GPGSA", "$GPGSV", "$GPRMC", "$GPVTG", "APRS Sentence"]
    static let gpsAutoTxOptions         = ["Off", "0.2 min", "0.5 min", "1 min", "2 min", "3 min", "5 min", "10 min", "20 min", "30 min", "60 min"]
    static let rxBreakInDisplayOptions  = ["Off", "All", "Related to DSQ", "My Station Only"]
    static let rxBreakInSizeOptions     = ["Half", "Entire"]
    static let rxBreakInHoldOptions     = ["0 sec", "3 sec", "5 sec", "10 sec", "20 sec", "30 sec", "60 sec", "Infinite"]
    static let callsignAnnounceOptions  = ["Off", "Kerchunk", "Except Kerchunk", "My Station Only", "All"]
    static let dvGatewayModeOptions     = ["Off", "Reflector TERM Mode"]
    static let dvGatewayInterfaceOptions = ["USB", "Bluetooth"]
    static let autoReplyOptions         = ["Off", "On", "On (Voice)"]
    static let autoReplyTimingOptions   = ["Immediate", "5 sec", "10 sec", "20 sec", "30 sec", "60 sec"]
    static let dataTxEndTimingOptions   = ["Off", "0.5 sec", "1 sec", "1.5 sec", "2 sec"]
    static let dataFrameOutputOptions   = ["All", "Related to DSQ", "DATA Mode"]
    static let digitalSquelchOptions    = ["Off", "Callsign Squelch", "Code Squelch"]
    static let digitalCodeOptions       = ["Off", "1", "2", "3", "4", "5"]
}

extension MemoryMap {
    func dstarSettings() -> DSTARSettings { DSTARSettings(from: raw) }
    func setDSTARSettings(_ s: DSTARSettings) { s.write(to: &raw) }
}
