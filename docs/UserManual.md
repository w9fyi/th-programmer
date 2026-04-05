# TH-Programmer User Manual

## Overview

TH-Programmer is a macOS application for programming and controlling the Kenwood TH-D75A/E (and TH-D74A/E) handheld transceivers. It provides full memory channel management, live real-time radio control, D-STAR reflector connectivity, and APRS configuration — all designed with VoiceOver accessibility as a first-class priority.

### System Requirements

- macOS 14 (Sonoma) or later
- Kenwood TH-D75A/E or TH-D74A/E
- USB-C cable (for clone mode and live control) or Bluetooth pairing
- Unsigned app — right-click and choose Open on first launch to bypass Gatekeeper

### Connecting Your Radio

TH-Programmer supports two connection methods:

**USB (recommended):**
1. Connect the TH-D75 to your Mac via USB-C cable.
2. The app will auto-detect the radio and show a banner: "TH-D75 detected."
3. Click "Select Port" in the banner, or choose the port manually from the port picker.
4. The port appears as `/dev/cu.usbmodemXXXXXXX`.

**Bluetooth:**
1. On the radio, go to Menu 930 and turn Bluetooth ON.
2. Pair the radio with your Mac via System Settings, Bluetooth.
3. In TH-Programmer, the Bluetooth port appears as `/dev/cu.TH-D75`.
4. Note: Bluetooth is currently supported for live CAT control. Clone mode (download/upload) requires USB.

---

## Main Window

The main window has seven tabs across the top, a toolbar, and a status bar at the bottom.

### Toolbar Buttons

- **Find Repeaters** — Search RepeaterBook for local repeaters and import them into empty channels.
- **Download** — Download all memory channels and settings from the radio (clone mode). Takes about 40 seconds.
- **Upload** — Upload modified channels and settings back to the radio. Takes about 40 seconds.
- **Live** — Connect live CAT control for real-time tuning, PTT, and settings changes without entering clone mode.

### Status Bar

The bottom of the window shows current status: connection state, progress during download/upload, and confirmation messages after actions.

### Radio Detection Banner

When you plug in a TH-D75 via USB, a banner appears automatically. Click "Select Port" to use that radio, or dismiss the banner with the X button.

---

## Tab 1: Memories

The Memories tab shows all 1000 memory channels (0–999) in a scrollable list.

### Viewing Channels

Each row shows the channel number, name, frequency, mode, and tone settings. Empty channels are shown but can be filtered out.

- Use the **Group** picker to filter by memory group (0–29).
- Use the **Filter** to show All, Used, or Empty channels.
- Click a channel to select it.

### Editing a Channel

Double-click a channel or select it and press Return to open the editor. The editor has these sections:

**Basic Settings:**
- Frequency (MHz) — type the frequency and it converts automatically
- Mode — FM, DV, AM, LSB, USB, CW, NFM, DR, WFM
- Duplex — Simplex, +Offset, -Offset, Split
- Offset (kHz) — repeater offset
- Tuning Step — 5 kHz through 100 kHz

**Tone/Squelch:**
- Tone Mode — None, Tone, CTCSS, DCS, Cross
- TX Tone and RX Tone frequency
- DCS code

**D-STAR (shown in DV/DR modes):**
- UR Call — destination callsign (CQCQCQ for simplex)
- RPT1 — access repeater callsign
- RPT2 — gateway repeater callsign
- DV Code

**Advanced:**
- Skip/Lockout — exclude from scan
- Group assignment (0–29)
- Channel name (up to 16 characters)

When you save a channel edit and live control is connected, the change is written to the radio immediately via the ME/MN commands.

---

## Tab 2: Call Channels

Shows the VHF, UHF, and 220 MHz call channels. These are special quick-access channels with some fields locked (mode cannot be changed on digital call channels).

---

## Tab 3: Scan Edges

Displays scan edge memory channels used for programmed scan ranges.

---

## Tab 4: Weather

Shows the 10 weather channels (WX1–WX10). These have fixed frequencies and most fields are read-only.

---

## Tab 5: DR Repeaters

Displays D-STAR DR (Digital Repeater) mode repeater entries for use with MMDVM hotspots and D-STAR repeaters.

---

## Tab 6: Hotspots

Hotspot discovery and management for MMDVM-compatible hotspots. Shows detected hotspots and allows connection.

---

## Tab 7: Reflector Gateway

The Reflector tab provides a full D-STAR internet gateway, allowing your TH-D75 to communicate through D-STAR reflectors (REF, XRF, DCS) over the internet via Bluetooth. The radio handles the AMBE voice codec — the app bridges the serial terminal mode data to and from the reflector network.

### Gateway Modes

The Reflector tab supports two gateway modes, selectable at the top:

- **MMDVM Terminal** (recommended) — Uses the TH-D75's built-in Reflector Terminal Mode (Menu 650). The radio handles all AMBE voice encoding/decoding. The app bridges the MMDVM serial data between the radio and the reflector over the internet. This mode provides full-quality D-STAR audio with no software codec required.

- **Software Codec** — Uses the mbelib software codec on your Mac with your Mac's microphone and speaker. This mode does not require the radio for audio but has lower audio quality than the hardware codec.

### Setting Up MMDVM Terminal Mode

Before connecting, configure your TH-D75:

1. **Enable Reflector Terminal Mode:** On the radio, go to Menu 650 (Reflector TERM Mode) and set it to ON.
2. **Pair Bluetooth:** If not already paired, go to Menu 930 on the radio and turn Bluetooth ON. Pair with your Mac via System Settings, Bluetooth.
3. **Select Gateway Mode:** In TH-Programmer, select "MMDVM Terminal" at the top of the Reflector tab.

### Connecting to the Radio

1. Click **Connect MMDVM** to open a direct Bluetooth RFCOMM connection to the radio.
2. The app will connect to the radio and probe for the MMDVM firmware. You should hear one "connection completed" tone from the radio.
3. Once connected, the status shows the firmware version (e.g., "TH-D75 RTM1.00") and the state changes to "Radio ready."

**Important notes:**
- Do NOT press the Bluetooth "Connect" button in the radio list before pressing Connect MMDVM. The MMDVM button handles the entire Bluetooth lifecycle. Connecting Bluetooth separately first will cause a double-connection that disrupts terminal mode.
- If the radio shows "No response from radio," verify Menu 650 is set to ON.
- If the connection fails on the first attempt, the app will retry automatically (up to 10 attempts).

### Connecting to a Reflector

1. Enter your callsign in the "My Callsign" field (e.g., AI5OS). This must be a valid amateur radio callsign registered for D-STAR.
2. Select the reflector type: **REF** (DPlus protocol), **XRF** (DExtra protocol), or **DCS**.
3. Enter the reflector number (e.g., 001).
4. Choose the module (A–Z). Module C is commonly used for general chat.
5. Click **Connect**.

For REF reflectors, the app first authenticates with the DPlus trust server (auth.dstargateway.org) to register your callsign and IP address. This is required for the reflector to accept your voice transmissions. After authentication, the app connects to the reflector via UDP.

The status will show "Connected" when the link is established. You will see keepalive exchanges in the connection log.

### Making a Transmission

Once both the radio and reflector are connected (status shows "Bridging active"):

1. Simply key the radio as you normally would (press PTT on the TH-D75).
2. The app automatically captures the MMDVM voice frames from the radio and forwards them to the reflector.
3. When you release PTT, the app sends an end-of-transmission marker.
4. Your transmission will appear on the reflector's dashboard (e.g., http://ref001.dstargateway.org) in the "Last Heard" list.

### Receiving Audio

When another station transmits on the reflector module you are connected to:

1. The app receives the voice frames from the reflector.
2. The frames are forwarded to your radio via the MMDVM serial bridge.
3. You hear the audio through your radio's speaker, just as if you were connected to a local repeater.

The "Heard Stations" section at the bottom of the Reflector tab shows recently heard callsigns with timestamps.

### URCALL Field and D-STAR Routing

The TH-D75 sends the URCALL (YOUR) field from its current DR/DV settings. Common URCALL values:

- **CQCQCQ** — General call to all stations on the module.
- **E** (in position 8) — Echo test. Note: the echo test is a gateway function, not a reflector function. The app does not currently implement local echo. To test your connection, make a CQCQCQ call or listen for other stations.
- A specific callsign — Direct call to another station.

### Favorites

Save frequently used reflector connections as favorites:

1. Connect to a reflector.
2. Click **Add Favorite** or use the menu item.
3. Enter a label (e.g., "Texas D-STAR Chat").
4. The favorite appears in the Favorites section for one-click reconnection.

### Reflector Directory

Click **Directory** to browse the full list of known D-STAR reflectors. The directory is fetched from official host files and the DPlus trust server. You can search by name or number and connect directly from the directory.

### Disconnecting

- **Disconnect** (reflector) — Disconnects from the reflector but keeps the radio MMDVM link open.
- **Disconnect MMDVM** — Disconnects the radio's Bluetooth MMDVM session entirely.

### Connection Log

The connection log at the bottom of the Reflector tab shows detailed diagnostic information including authentication, registration, and packet flow. This is useful for troubleshooting connection issues.

### Troubleshooting Reflector Connections

**Radio says "connection completed" twice:**
This should not happen with the current version. If it does, disconnect MMDVM and reconnect. The app handles Bluetooth connection management automatically.

**"No response from radio" after connecting:**
- Verify Menu 650 (Reflector TERM Mode) is set to ON.
- Power cycle Bluetooth on the radio (Menu 930, OFF then ON).
- Ensure no other app is using the Bluetooth connection.

**Reflector connects but nobody hears you:**
- Verify your callsign is registered for D-STAR at https://regist.dstargateway.org
- Check that the reflector dashboard shows your callsign in "Last Heard" after transmitting.
- Try a different reflector module or reflector.

**Audio is choppy on long received transmissions:**
- This can occur due to network jitter. The app uses adaptive frame pacing to minimize this. Ensure your internet connection is stable.

**Cannot connect to XRF reflectors:**
- XRF (DExtra) reflector support requires the reflector to be online and accessible on UDP port 30001. Some XRF reflectors may be offline or have restricted access.

---

## Live Control

Live Control provides real-time radio control via CAT commands over USB. No clone mode download is needed — changes take effect instantly on the radio.

### Connecting

Click the **Live** button in the toolbar. The app opens a 9600 baud CAT session, identifies the radio, and begins polling the VFO state every 500 ms.

### Frequency Display

The top of the Live Control panel shows:
- Current frequency in MHz (large monospaced text)
- VFO indicator (A or B)
- Current mode (FM, DV, AM, LSB, USB, CW, etc.)
- S-meter readings for both bands (updated in real-time)

### Tuning

- **Direct entry:** Type a frequency in MHz in the text field and click Tune or press Return.
- **Step buttons:** Click the up/down arrows to step by one tuning step.
- **Tuning Step picker:** Change the step size (5 kHz through 100 kHz).

### VFO and Mode

- **VFO:** Switch between VFO A and VFO B.
- **Mode:** Pick from FM, DV, AM, LSB, USB, CW, NFM, DR, WFM. Note: some modes are only available on certain bands (e.g., LSB/USB below 174 MHz).
- **VFO/MR:** Switch between VFO mode, Memory mode, and Call mode.

### Radio Settings

The Radio Settings group provides live control of:

- **AF Gain** — Audio volume (0–200)
- **Backlight** — Manual, On, Auto, or Auto DC-in
- **Bar Antenna** — External or Internal
- **Power Save** — Displayed as read-only (not writable via CAT)
- **Dual Band** — Toggle between dual and single band display
- **VOX** — Toggle voice-operated transmit on/off
- **VOX Gain** — Sensitivity (0–9)
- **VOX Delay** — Hang time (250 ms to 3000 ms)
- **Attenuator A/B** — Toggle per-band receive attenuator

### TX Power

Set transmit power for each band independently:
- High, Medium, Low, or EL (Extra Low)

### Radio Info

Once connected, the app fetches and displays:
- Callsign (editable — type and press Return or click Set)
- Firmware version
- Serial number and model variant
- GPS clock (UTC, synced from radio's GPS)
- GPS fix status and position coordinates
- Speed (when moving)

### APRS

- **Send Beacon** — Trigger a single APRS position beacon. The radio's TNC must be on.

### D-STAR Reflector (DV/DR modes only)

When the radio is in DV or DR mode, a reflector terminal section appears:
- Select type (REF, XRF, DCS), number, and module
- Connect, Disconnect, or query Info
- Status updates shown in real-time

### Disconnecting

Click **Disconnect** to end the live session, or **Done** to close the panel and keep the connection running in the background (the toolbar will show the current frequency).

---

## APRS Settings

Access APRS settings from the window menu or the APRS tab. This view has two modes:

### Live Radio Control (when connected)

When the radio is connected via live CAT, three settings can be changed in real-time:

- **TNC Mode** — Off or APRS (turns the packet TNC on/off)
- **Beacon Mode** — Manual, PTT, Auto, or SmartBeaconing
- **Position Source** — GPS or one of 5 stored positions
- **Send Beacon** — Trigger an immediate APRS beacon

### Clone Mode Settings (when memory image is loaded)

The full APRS configuration is available when a memory image is loaded (via download or file open):

- **My Station:** Callsign, SSID, position comment, symbol
- **Beacon:** Mode, interval, decay algorithm, proportional pathing, speed/altitude inclusion
- **SmartBeaconing:** Low/high speed thresholds, slow/fast rates, turn angle/slope/time
- **Path:** Digipeater path type, WIDE1-1, total hops
- **Status Texts:** Up to 5 status messages with individual TX rates
- **Data:** Band, speed (1200/9600), TX delay, DCD sense

Click **Save** to write changes to the memory image. Upload to the radio to apply.

---

## Radio Settings

Access from the window menu. Edit radio-wide settings stored in the clone blob:

- **Radio:** Beat shift, TX inhibit, time-out timer, mic sensitivity, WX alert, auto repeater shift
- **Filters:** SSB high cut, CW width, AM high cut
- **Scan:** Resume mode, time/carrier restart, priority scan
- **VOX:** Enable, gain, delay
- **DTMF:** Encode speed, hold, pause
- **CW:** Pitch, reverse
- **Display:** Backlight, brightness, meter type, background color, single band display
- **Audio:** Balance, beep, beep volume, voice guidance, USB audio
- **Power:** Battery saver, auto power off
- **Bluetooth:** Enable, auto connect
- **PF Keys:** PF1, PF2, mic PF1/PF2/PF3 assignments
- **Lock:** DTMF lock, mic lock, volume lock
- **Units:** Speed, altitude, temperature, lat/long format, grid square

Click **Save** to write changes to the memory image. Upload to the radio to apply.

---

## D-STAR Settings

Edit D-STAR configuration stored in the clone blob:

- **My Station:** Callsign (8 chars) + suffix (4 chars)
- **TX Messages:** Up to 5 messages (20 chars each)
- **Repeater Routing:** A-band and B-band UR/RPT1/RPT2 calls
- **DV Options:** Direct reply, auto reply timing, data TX end timing, EMR volume, RX AFC, FM auto detect
- **Digital Squelch:** Off, code squelch, or callsign squelch
- **GPS Data TX:** GPS info in frame, NMEA sentence, auto TX interval
- **RX Notification:** Break-in display, size, hold time, callsign announce, standby beep

---

## RepeaterBook Search

Click **Find Repeaters** in the toolbar to search the RepeaterBook database.

1. Select a state (required).
2. Optionally filter by county and/or band.
3. Click Search.
4. Results show callsign, frequency, offset, tone, and location.
5. Select repeaters and click Import to fill them into empty memory channels.

---

## File Operations

### Save/Open Files

- **File, Save** — Save the current memory image to a .d75 file.
- **File, Open** — Load a .d75 or .d74 file from disk.
- Files use the standard Kenwood format (256-byte header + raw blob) and are compatible with the official Kenwood MCP-D75 software.

### Download/Upload

- **Download** reads the entire memory from the radio via clone mode (USB only, ~40 seconds).
- **Upload** writes the entire memory back to the radio. The radio reboots after upload.
- Progress is shown in the status bar with percentage updates.

---

## VoiceOver Accessibility

TH-Programmer is designed VoiceOver-first. Every control has a descriptive accessibility label and hint.

### Key VoiceOver Features

- **Frequency announcements:** The live control panel announces frequency changes.
- **Status announcements:** Download/upload progress, connection state, and errors are announced as live region updates.
- **Channel editing:** All form fields have labels describing the setting and its current value.
- **S-meter:** Signal strength readings update frequently and are marked as live content.
- **Reflector status:** Link/unlink confirmations are announced.
- **Detection banner:** Radio connection via USB or Bluetooth is announced when detected.

### Keyboard Navigation

- Tab through all controls in the live panel.
- Return submits frequency entry and callsign changes.
- Escape closes sheet panels.
- Standard macOS keyboard shortcuts work throughout (Command-S to save, etc.).

---

## Troubleshooting

### Radio not detected

- Ensure the USB-C cable is a data cable (not charge-only).
- Try a different USB port on your Mac.
- On the radio: Menu 980 (USB Function) must be set to "COM+AF/IF Output" (not Mass Storage).
- After clone mode, the USB port may drop temporarily. Unplug and replug the cable if needed.

### Clone mode download/upload fails

- Clone mode requires USB — Bluetooth is not supported for clone operations.
- Make sure no other app (CHIRP, MCP-D75, etc.) has the serial port open.
- If the radio beeps and the download stalls, power-cycle the radio and try again.

### Live control: all commands return N

- The radio may be in D-STAR DR mode, which blocks most write commands.
- Switch the radio to FM or VFO mode before connecting live control.
- Check that no key lock is engaged on the radio.

### Live control: no response from radio

- Verify the correct port is selected (USB modem, not Bluetooth or other devices).
- The radio must be powered on and not in clone/programming mode.
- Try disconnecting and reconnecting.

### Bluetooth: port opens but no response

- The `/dev/cu.TH-D75` Bluetooth port opens but does not respond to CAT commands on firmware 1.03.
- This is a known limitation. Use USB for all operations until Bluetooth CAT is resolved.
- Bluetooth TNC/KISS mode may work separately from CAT.

### Settings don't match after upload

- Some settings use inverted encoding: Mic Sensitivity (0=High, 2=Low), Brightness (0=Low, 2=High), Voice Guidance (Auto1 and Auto2 are swapped in the blob).
- AF Gain and D-Star active slot are volatile — they are not stored in the clone blob and reset on power cycle.

---

## Technical Reference

For developers and advanced users, detailed technical documentation is available in the `docs/` folder:

- **TH-D75-CAT-Reference.md** — Complete CAT command specification with all 43 hardware-verified commands, parameter ranges, and constraints.
- **TH-D75-Blob-Offset-Map.md** — Memory blob byte offset map with verification status for every radio setting.

---

## About

TH-Programmer is an open-source project for the amateur radio community.

- Radio: Kenwood TH-D75A/E and TH-D74A/E
- Platform: macOS 14+
- Accessibility: VoiceOver-first design
- Protocol: Reverse-engineered from CHIRP, Hamlib, and the LA3QMA TH-D74 command reference, then hardware-verified against the TH-D75 (firmware 1.03)
