# TH-D75 Memory Blob Offset Map
# Hardware-verified via CAT-change + blob-diff and menu-change + blob-diff
# Radio: S/N C5310165, firmware 1.03
# Date: 2026-04-02

## Overview
- Clone blob size: 172,800 bytes (0x2A300)
- Clone protocol: 675 blocks x 256 bytes, 57600 baud
- D75 settings block shifted -0x100 from D74 (0x1100 → 0x1000)
- APRS block UNCHANGED from D74 (0x1200+, 0x1360+)
- Channel memory layout UNCHANGED from D74 (0x4000+)

## Verification Methods
- ✓ CAT: Changed setting via CAT command, downloaded blob, diffed
- ✓ Menu: Changed setting on radio menu, downloaded blob, diffed
- TODO: Offset shifted by -0x100 from D74, not yet hardware-verified

## RadioSettings Block (0x1000–0x10BF)

| Offset | Setting | Verified | Menu | Values |
|--------|---------|----------|------|--------|
| 0x1000 | beatShift | TODO | 101 | 0=Off 1=On |
| 0x1001 | txInhibit | TODO | 110 | 0=Off 1=On |
| 0x1002 | detectOutSelect | TODO | 102 | 0=AF 1=IF 2=Detect |
| 0x1003 | timeOutTimer | ✓ Menu | 111 | 0=0.5min … 5=3.0min … 10=10.0min |
| 0x1005 | barAntenna | ✓ CAT | 104 | 0=external 1=internal |
| 0x1006 | micSensitivity | ✓ Menu | 112 | 0=High 1=Med 2=Low (INVERTED!) |
| 0x1007 | wxAlert | TODO | 105 | 0=Off 1=On |
| 0x1008 | ssbHighCut | ✓ CAT | 120 | 0=2.2k 1=2.4k 2=2.6k 3=2.8k 4=3.0k |
| 0x1009 | cwWidth | ✓ CAT+Menu | 121 | 0=0.3k 1=0.5k 2=1.0k 3=1.5k 4=2.0k |
| 0x100A | amHighCut | ✓ CAT+Menu | 122 | 0=3.0k 1=4.5k 2=6.0k 3=7.5k |
| 0x100C | scanResumeAnalog | ✓ Menu | 130 | 0=Time 1=Carrier 2=Seek |
| 0x100D | scanResumeDigital | TODO | 131 | 0=Time 1=Carrier 2=Seek |
| 0x100E | scanTimeRestart | ✓ Menu | 132 | value in seconds |
| 0x100F | scanCarrierRestart | TODO | 133 | value in seconds |
| 0x1011 | priorityScan | TODO | 134 | 0=Off 1=On |
| 0x1012 | scanAutoBacklight | TODO | 135 | 0=Off 1=On |
| 0x1013 | scanWeatherAuto | TODO | 136 | 0=Off 1=On |
| 0x1017 | autoRepeaterShift | TODO | 141 | 0=Off 1=On |
| 0x1018 | callKey | TODO | 142 | assignment index |
| 0x1019 | toneBurstHold | TODO | 143 | 0=Off 1=On |
| 0x101B | voxEnabled | ✓ CAT | 150 | 0=Off 1=On |
| 0x101C | voxGain | ✓ CAT | 151 | 0–9 |
| 0x101D | voxDelay | ✓ CAT+Menu | 152 | 0=250ms 1=500ms … 5=2000ms 6=3000ms |
| 0x101E | voxHysteresis | TODO | 153 | 0=Off 1=On |
| 0x101F | dtmfSpeed | ✓ Menu | 160 | 0=50ms 1=100ms 2=150ms |
| 0x1020 | dtmfHold | TODO | 162 | 0=Off 1=On |
| 0x1021 | dtmfPause | ✓ Menu | 161 | pause time index |
| 0x1024 | cwPitch | ✓ Menu | 170 | 0=400Hz … 4=800Hz … 6=1000Hz |
| 0x1025 | cwReverse | TODO | 171 | 0=Normal 1=Reverse |
| 0x1026 | qsoLog | ✓ Menu | 180 | 0=Off 1=On |
| 0x1030 | recallMethod | TODO | 202 | 0=AllBands 1=CurrentBand |
| 0x1031 | audioRecordingBand | TODO | 302 | 0=A 1=B 2=Both |
| 0x1032 | audioTxMonitor | TODO | 311 | 0=Off 1=On |
| 0x1040 | fmRadioEnabled | TODO | 700 | 0=Off 1=On |
| 0x1041 | fmRadioAutoMute | TODO | 701 | 1–10 sec |
| 0x1060 | displayBacklight | ✓ CAT | 900 | 0=Auto 1=Auto(DC-IN) 2=Manual 3=On |
| 0x1061 | displayBacklightTimer | TODO | 901 | 3–60 sec |
| 0x1062 | displayBrightness | ✓ Menu | 902 | 0=Low 1=Medium 2=High (INVERTED!) |
| 0x1063 | displaySingleBand | TODO | 904 | 0=Off 1=GPS(Alt) 2=GPS(GS) 3=Date 4=Demod |
| 0x1064 | displayMeterType | ✓ Menu | 905 | 0=Type1 1=Type2 2=Type3 |
| 0x1065 | displayBgColor | ✓ Menu | 906 | 0=Black 1=White |
| 0x1066 | audioBalance | TODO | 910 | 0–10 (5=center) |
| 0x1071 | beep | ✓ Menu | 914 | 0=Off 1=On |
| 0x1072 | beepVolume | ✓ Menu | 915 | 0=VolLink 1–7=Level |
| 0x1073 | voiceGuidance | ✓ Menu | 916 | 0=Off 1=Manual 2=Auto2 3=Auto1 (2/3 SWAPPED!) |
| 0x1074 | voiceGuidanceVolume | TODO | 917 | 0=VolLink 1–7=Level |
| 0x1075 | usbAudio | TODO | — | 0=Off 1=On |
| 0x1076 | batterySaver | ✓ Menu | 920 | 0=Off 1=0.2s … 6=2.0s … 9=5.0s |
| 0x1077 | autoPowerOff | ✓ Menu | 921 | 0=Off 1=15min 2=30min 3=60min |
| 0x1078 | btEnabled | ✓ CAT | 930 | 0=Off 1=On |
| 0x1079 | btAutoConnect | TODO | 936 | 0=Off 1=On |
| 0x107A | pf1Key | ✓ Menu | 940 | assignment index |
| 0x107B | pf2Key | TODO | 941 | assignment index |
| 0x107C | pf1MicKey | TODO | 942 | assignment index |
| 0x107D | pf2MicKey | TODO | 943 | assignment index |
| 0x107E | pf3MicKey | TODO | 944 | assignment index |
| 0x107F | cursorShift | TODO | 945 | 0=Off, else sec |
| 0x1086 | keysLockType | TODO | 960 | 0=KeyLock 1=FreqLock |
| 0x1087 | dtmfLock | TODO | 961 | 0=Off 1=On |
| 0x1088 | micLock | ✓ Menu | 963 | 0=Off 1=On |
| 0x1089 | volumeLock | TODO | 963 | 0=Off 1=On |
| 0x108C | tempUnit/latLongUnit | ✓ Menu | 972/973 | confirmed byte changed |

## Per-Band VFO Settings (0x0300–0x03FF)

| Offset | Setting | Verified | Description |
|--------|---------|----------|-------------|
| 0x0300–0x030B | Band A VFO state | ✓ Diff | Freq + step + mode (encoded) |
| 0x0359 | aBandTxPower | ✓ CAT | 0=High 1=Med 2=Low 3=EL |
| 0x035B | aBandSquelch | ✓ CAT | 0–5 |
| 0x035C | aBandAttenuator | ✓ CAT | 0=Off 1=On |
| 0x0369 | bBandTxPower | ✓ CAT | 0=High 1=Med 2=Low 3=EL |
| 0x036B | bBandSquelch | ✓ CAT | 0–5 |
| 0x0396 | dualBandMode | ✓ CAT | 0=Dual 1=Single |
| 0x0400–0x040B | Band A VFO shadow | ✓ Diff | Mirror of 0x0300 area |

## APRS Block (0x1200+ — unchanged from D74)

| Offset | Setting | Verified | Description |
|--------|---------|----------|-------------|
| 0x1200–0x1208 | myCallsign+SSID | ✓ CAT+Diff | CS command |
| 0x120C | dataSpeed | ✓ CAT+Diff | AS: 0=1200 1=9600 |
| 0x136A | beaconMode | ✓ CAT+Diff | PT: 0=manual … 3=smart |
| 0x02B0 | positionSource | ✓ CAT | MS: 0=GPS 1-5=stored |

See RadioSettings.swift and APRSSettings.swift for complete APRS/D-STAR offset maps.

## Encoding Quirks
- **Mic Sensitivity** (0x1006): 0=High, 1=Med, 2=Low — inverted from menu label order
- **Brightness** (0x1062): 0=Low, 1=Medium, 2=High — inverted from menu label order
- **Voice Guidance** (0x1073): 0=Off, 1=Manual, 2=Auto2, 3=Auto1 — Auto1/Auto2 swapped
- **Backlight** (0x1060): CAT `LC` uses 0=manual 1=on 2=auto 3=auto-DC; blob matches
- **VOX order**: D74 was gain/delay/enabled; D75 is enabled/gain/delay (reordered!)

## Volatile Settings (NOT in clone blob)
- AF Gain (AG) — runtime only
- D-Star Active Slot (DS) — runtime only
- S-Meter (SM) — runtime only
- Squelch Status (BY) — runtime only
