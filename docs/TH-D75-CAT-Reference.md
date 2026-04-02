# TH-D75 CAT Command Reference
# Hardware-verified against S/N C5310165, firmware 1.03
# Port: USB CDC-ACM (cu.usbmodem*), 9600 baud 8N1, CR terminator
# Date: 2026-04-02

## Protocol Notes
- Line terminator: `\r` (CR only — not LF, not CRLF, not semicolon)
- Baud rate: 9600 (CAT mode), 57600 (clone mode)
- Error responses: `?` = unrecognized command, `N` = recognized but cannot execute
- The D75 uses D74-style commands with band parameters (0=Band A, 1=Band B)
- FA/FB/MU/MC/DTM/DGW/IF/EX commands DO NOT EXIST on firmware 1.03
- Many write commands return `N` when radio is in D-STAR DR mode — switch to FM/VFO first
- AF Gain and D-Star active slot are volatile — not stored in clone blob
- On connect: send `AI 0\r` to disable unsolicited auto-info

## Confirmed Read + Write (31 commands)

| Command | Syntax | Range | Description |
|---------|--------|-------|-------------|
| FQ | `FQ band,freq` | band 0/1, freq 10-digit Hz | Frequency |
| FO | `FO band,...21 params` | See LiveRadioState | Full VFO state |
| ME | `ME ch,...23 params` | ch 000-999, p2=C to clear | Memory channel |
| MR | `MR band,ch` | Only in MR mode (VM=1) | Memory recall |
| MD | `MD band,mode` | mode 0-9, band-dependent | Operating mode |
| VM | `VM band,mode` | 0=VFO 1=MR 2=Call 3=DV | VFO/Memory mode |
| SQ | `SQ band,level` | 0-5 (decimal, not hex!) | Squelch |
| AG | `AG nnn` | 000-200 (not 255!) | AF gain/volume |
| PC | `PC band,level` | 0=High 1=Med 2=Low 3=EL | TX power |
| BC | `BC band` | 0=A 1=B | PTT/CTRL band |
| RA | `RA band,on` | 0=off 1=on | Attenuator |
| SH | `SH mode,width` | mode: 0=SSB 1=CW 2=AM | DSP filter width |
| SF | `SF band,step` | step index 0-B (hex) | Tuning step |
| VX | `VX on` | 0=off 1=on | VOX on/off |
| VG | `VG gain` | 0-9 | VOX gain |
| VD | `VD delay` | 0=250ms thru 6=3000ms | VOX delay |
| LC | `LC mode` | 0=manual 1=on 2=auto 3=DC-in | Backlight |
| BT | `BT on` | 0=off 1=on | Bluetooth |
| BS | `BS ant` | 0=external 1=internal | Bar antenna |
| DL | `DL mode` | 0=dual 1=single | Dual/single band |
| DS | `DS slot` | 1-6 | Active D-Star slot |
| DC | `DC slot,call,msg` | slot 1-6 | D-Star callsign slot |
| CS | `CS call` | up to 9 chars with SSID | APRS callsign |
| TN | `TN mode,band` | 0=off 1=APRS (avoid 2=KISS!) | TNC mode |
| PT | `PT mode` | 0=manual 1=PTT 2=auto 3=smart | Beacon mode |
| MS | `MS source` | 0=GPS 1-5=stored | Position source |
| AS | `AS rate` | 0=1200 1=9600 | TNC baud rate |
| GP | `GP gps,pc` | each 0/1 | GPS + PC output |
| GS | `GS g,g,g,g,g,g` | 6 toggles for NMEA sentences | GPS sentences |
| GM | `GM mode` | 0=normal (1=GPS-only RESTARTS!) | Radio/GPS mode |
| AI | `AI on` | 0=off 1=on | Auto-info |

## Confirmed Read-Only (7 commands)

| Command | Syntax | Response Example | Description |
|---------|--------|-----------------|-------------|
| ID | `ID` | `ID TH-D75` | Model ID |
| TY | `TY` | `TY K,2` | Market code (K=USA, 2=std) |
| AE | `AE` | `AE C5310165,K01` | Serial + model |
| FV | `FV` | `FV 1.03` | Firmware version |
| BL | `BL` | `BL 3` | Battery (0=empty 3=full 4=charging) |
| SM | `SM band` | `SM 0,3` | S-meter reading |
| BY | `BY band` | `BY 0,1` | Squelch status (0=closed 1=open) |
| RT | `RT` | `RT 260402015913` | Clock (YYMMDDHHMMSS) |

## Confirmed Action Commands (5)

| Command | Response | Description |
|---------|----------|-------------|
| TX | `TX band` | Transmit (PTT on) |
| RX | `RX` | Receive (PTT off) |
| UP | `UP` | Step frequency up |
| DW | `DW` | Step frequency down |
| BE | `BE` or `N` | APRS beacon trigger (N=TNC off) |

## Not Supported (firmware 1.03)

| Command | Status | Notes |
|---------|--------|-------|
| FA / FB | `?` | TS-890 style freq — not on D75 |
| IF | `?` | Composite status string — not on D75 |
| MU | `?` | Menu system — not available via CAT |
| MC | `?` | Memory select — use ME/MR instead |
| DTM | `?` | Reflector terminal — not via CAT |
| DGW | `?` | DV Gateway — not via CAT |
| QUITS | `?` | Exit command — not on D75 |
| EX | `?` | Extended menu — not on D75 |
| MN | `?` | Memory name — not on D75 (use ME) |
| PS write | `?` | Power save — read-only via CAT |
| FR write | `N` | FM radio — read-only via CAT |
| FT write | `N` | Fine tune — not writable via CAT |
| FS write | `N` | Fine step — not writable via CAT |

## Write Constraints

- **DR mode blocks most writes** — switch to FM/VFO before writing
- **MD mode changes are band-dependent** — can't set LSB on UHF
- **TN 1,1 (APRS on Band B)** — may return N depending on CTRL band
- **MR only works in memory mode** — returns N when VM=0 (VFO)
- **GS can't disable ALL sentences** — at least one must stay on
- **GM 1 restarts the radio** in GPS-only mode — use with extreme caution

## Tuning Step Index Table (SF command)

| Index | Step |
|-------|------|
| 0 | 5 kHz |
| 1 | 6.25 kHz |
| 2 | 8.33 kHz (airband only) |
| 3 | 9 kHz (MW only) |
| 4 | 10 kHz |
| 5 | 12.5 kHz |
| 6 | 15 kHz |
| 7 | 20 kHz |
| 8 | 25 kHz |
| 9 | 30 kHz |
| A | 50 kHz |
| B | 100 kHz |

## Mode Index Table (MD command)

| Index | Mode |
|-------|------|
| 0 | FM |
| 1 | DV (D-Star voice) |
| 2 | AM |
| 3 | LSB |
| 4 | USB |
| 5 | CW |
| 6 | NFM (narrow FM) |
| 7 | DR (D-Star repeater) |
| 8 | WFM (wideband FM) |
| 9 | R-CW (reverse CW) |

## DSP Filter Width Table (SH command)

**SSB (SH 0,n):** 0=2.2k 1=2.4k 2=2.6k 3=2.8k 4=3.0k
**CW (SH 1,n):** 0=0.3k 1=0.5k 2=1.0k 3=1.5k 4=2.0k
**AM (SH 2,n):** 0=3.0k 1=4.5k 2=6.0k 3=7.5k
