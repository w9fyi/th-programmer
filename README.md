# th-programmer

**VoiceOver-first programmer and live CAT controller for the Kenwood TH-D75A/E and TH-D74A/E handhelds.**

The factory programming software for the TH-D75 and TH-D74 is Windows-only and is not usable with a screen reader. `th-programmer` is a native macOS app that does the same job — and a few jobs the factory tool does not — while being fully accessible from the first launch.

## What it does

- **Memory channel programming** — read, edit, and write the radio's memory channels
- **Live CAT control** — drive the radio in real time over USB or Bluetooth using the TH-D75's terminal mode (38400 baud, MMDVM-style framing)
- **Configuration management** — settings, menus, scan groups, and the bits of the radio that the front panel hides
- **Import / export** — move channel sets in and out so you can share them, version them, and back them up
- **VoiceOver-first** — every control is reachable, labeled, and operable without a mouse or a working pair of eyes

## Supported radios

- **Kenwood TH-D75A** and **TH-D75E** (primary target)
- **Kenwood TH-D74A** and **TH-D74E** (shared protocol — most features apply)

## Status

Active development. The terminal-mode protocol is reverse-engineered against the radio itself and validated against the factory software's wire traffic. If you have a TH-D75 or TH-D74 and you have hit accessibility walls trying to program it on macOS, please open an issue — that feedback directly shapes the roadmap.

## Why it exists

Kenwood ships excellent radios and inaccessible software. The TH-D75 in particular is a genuinely interesting handheld — APRS, D-STAR, dual receive, GPS — and almost none of the configuration is reachable from the front panel without significant patience. The official PC programming software runs only on Windows and the visual layout makes it effectively unusable with NVDA or JAWS for some operations. macOS users had nothing.

This project is the "macOS users had nothing" fix.

## Author

Justin Mann — **AI5OS**, Austin, Texas. Blind macOS developer building accessible amateur radio software.
Profile: [github.com/w9fyi](https://github.com/w9fyi) · Email: w9fyi@me.com

## License

Apache-2.0.
