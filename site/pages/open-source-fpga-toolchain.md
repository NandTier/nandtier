---
slug: open-source-fpga-toolchain
title: Open-source FPGA toolchain for Gowin · Yosys, nextpnr, Apicula
nav: Toolchain
description: Build a Gowin Tang Nano 9K or 20K bitstream with open-source tools only: Yosys, nextpnr-himbaechel, Apicula gowin_pack and openFPGALoader, plus RISC-V GCC, installed offline-capable by one script.
---
# Open-source FPGA toolchain

**Every NandTier bitstream is built with open-source tools only: no vendor IDE, no licence.** One script installs them, and `make fpga` runs the whole flow in about a minute and a half.

## The flow

| Board | Synthesis | Place and route | Bitstream | Programming |
|---|---|---|---|---|
| Tang Nano 9K / 20K (Gowin) | Yosys | nextpnr-himbaechel | Apicula `gowin_pack` | openFPGALoader |
| ULX3S (Lattice ECP5) | Yosys | nextpnr-ecp5 | Trellis `ecppack` | openFPGALoader |

The open flow reads none of the Gowin files. `boards/common/nt_rams.v` replaces the Gowin RAM IP with portable Verilog, and the boot RAM loads the boot ROM straight from the firmware build at synthesis.

## One-step install

```bash
setup/setup.sh            # Linux, macOS, WSL
setup\setup.bat           # Windows
```

It installs the YosysHQ OSS CAD Suite, the xPack RISC-V GCC and pyserial into `tools/`, writes `local.mk` so plain `make` finds them, and checks everything by building the firmware. Versions are pinned, archives are checked by SHA-256 where published, and running it again only adds what is missing. Uninstall by deleting `tools/` and `local.mk`.

## For a classroom without internet

```bash
setup/setup.sh --bundle                       # this OS
setup/setup.sh --bundle --platform win32-x64  # for Windows PCs
setup/setup.sh --offline                      # on each lab machine
```

## Checking the open flow

`make -C oss gatesim BOARD=tangnano9k` simulates the synthesised netlist with Gowin's own primitive models: it pings the boot ROM over the UART, programs a flash page and measures the HDMI clock. The Gowin IDE flow in `project/` is still there for comparison.

## Continuous integration

Every push to the NandTier repository installs the tools with the same script, builds the firmware, runs the test suite and builds the Tang Nano 9K and 20K bitstreams on GitHub Actions. Tagged versions publish the bitstreams as a release.
