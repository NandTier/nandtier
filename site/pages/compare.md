---
slug: compare
title: NandTier vs PicoRV32, NEORV32, VexRiscv and picotiny
nav: Compare
description: How NandTier compares with other open-source RISC-V cores and SoCs for FPGAs (PicoRV32, NEORV32, VexRiscv and Sipeed picotiny), and when to choose which.
---
# NandTier compared

**NandTier is not the smallest or the fastest RISC-V core. It is a complete, small computer made to be read end to end:** CPU, bus, boot ROM, flash, video, SD card, games and tests, in one repository that builds on a $25 board with open-source tools.

| | NandTier | PicoRV32 | NEORV32 | VexRiscv | picotiny |
|---|---|---|---|---|---|
| What it is | complete SoC + software + games | CPU core | microcontroller SoC | configurable CPU core | Tang Nano 9K example SoC (PicoRV32) |
| Language | Verilog | Verilog | VHDL | SpinalHDL (generates Verilog) | Verilog |
| Main goal | teaching the whole stack | small size | full-featured MCU | performance, configurability | board demo |
| HDMI graphics | tiles, sprites, text | not included | not included | not included | text terminal |
| Games and a game SDK | 8 games, C SDK | no | no | no | no |

Information about the other projects is from their public repositories; check them for current features.

## When to choose NandTier

- You want to **teach or learn how a whole computer works**, from reset to a game on screen, in code small enough to read.
- You have a **Tang Nano 9K or 20K**, or a ULX3S, and want HDMI output and storage out of the box.
- You want a **fully open-source flow** and a test suite to build on.

## When to choose something else

- **Smallest core for your own SoC:** PicoRV32.
- **A full-featured microcontroller** with interrupts, many peripherals and documentation in depth: NEORV32.
- **Performance, caches, Linux-capable configurations:** VexRiscv.

NandTier began as a modified copy of Sipeed's picotiny example. Every part of that has since been replaced by new code, under the Apache 2.0 licence.
