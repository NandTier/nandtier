---
slug: getting-started
title: Getting started with NandTier on the Tang Nano 9K
nav: Getting started
description: Install the open-source FPGA and RISC-V tools with one script, build NandTier, load it into a Tang Nano 9K, program the flash and SD card, and play the games.
---
# Getting started

**You need a Sipeed Tang Nano 9K, a USB-C cable, an HDMI screen and a microSD card.** On a PC with Linux, macOS or Windows, one script installs every tool; then four commands build the system, load it into the FPGA and put the software on the board.

## 1. Get the code and the tools

```bash
git clone https://github.com/NandTier/nandtier.git
cd nandtier
setup/setup.sh          # Linux, macOS, WSL. On Windows: setup\setup.bat
```

The script downloads about 1 GB once and installs everything into `tools/` inside the folder: nothing system-wide, no administrator rights. Versions are pinned in `setup/versions.txt`, so every computer gets the same tools.

| Tool | Used for |
|---|---|
| OSS CAD Suite | Yosys, nextpnr, Apicula, openFPGALoader, Icarus Verilog, GTKWave |
| xPack RISC-V GCC | the boot ROM, the launcher and the games |
| pyserial | the flash programmer and the keyboard controller |

**No internet in the lab?** On one machine run `setup/setup.sh --bundle`, copy the archive to the others, and install with `setup/setup.sh --offline`.

## 2. Build and test

```bash
make          # boot ROM, launcher and the eight games
make test     # the test suite, about a minute
```

## 3. Load the FPGA

```bash
make fpga         # the bitstream, about 1.5 minutes
make fpga-load    # into the FPGA, until power-off
make fpga-flash   # or: into the configuration flash, permanent
```

No tools yet? Each [GitHub release](https://github.com/NandTier/nandtier/releases/latest) has a ready bitstream: `openFPGALoader -b tangnano9k nandtier-tangnano9k.fs`.

## 4. Program the flash and the SD card

Put the microSD card in the board, then:

```bash
make program COMx=/dev/ttyUSB1     # Windows: COMx=COM5
```

Press the board's reset button when the script asks. The boot ROM answers, the launcher goes into the SPI flash, and the games go onto the SD card. See [Boot ROM and XIP flash](boot-rom-and-flash.html) for what happens on the wire.

## 5. Play

```bash
python3 sw/gamepad.py /dev/ttyUSB1
```

The game menu opens on the HDMI screen, and your PC keyboard becomes the controller: arrows to move, Space for A, Enter to start, Esc to quit. More in [Games](games.html).

## Next steps

- Read the [SoC architecture](architecture.html) to see how the parts connect.
- Change the C in `fw/fw-flash` and run `make program` again: that is the whole development loop.
- Write your own game with the [game SDK](games.html#writing-a-game).
