# Changelog

All notable changes to NandTier. The format follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow [Semantic Versioning](https://semver.org/).

## [1.0.0] - 2026-11-22

First public release.

### Hardware
- RV32IM CPU core, written from scratch.
- System bus with flash (execute in place, 4 KiB read cache), SRAM, on-chip I/O and external devices.
- Boot ROM in boot RAM; SPI flash controller with XIP and bit-bang modes.
- UART, GPIO, SD card (SPI), integrated logic analyzer.
- HDMI: picture processing unit (tiles, sprites, scrolling, palettes) and an 80x25 text terminal.
- Boards: Sipeed Tang Nano 9K, Sipeed Tang Nano 20K, Radiona ULX3S, with open-source bitstreams.

### Firmware and tools
- Boot ROM with a UART flash and SD programmer; launcher with a game menu.
- Game SDK and eight games on an SD card pack.
- `setup/setup.sh` and `setup.bat`: one-step, offline-capable tool installation.
- Test suite: CPU, peripherals, video, random programs against an instruction-set simulator, programmer, games.
