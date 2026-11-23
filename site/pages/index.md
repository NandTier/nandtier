---
slug: index
title: NandTier · an open-source RISC-V computer for the Tang Nano 9K
nav: Home
description: NandTier is an open-source RISC-V (RV32IM) system-on-chip for the $25 Sipeed Tang Nano 9K FPGA, with HDMI graphics, execute-in-place SPI flash, an SD card and eight games. Built with open-source tools.
---
<div class="hero">
<p class="kicker">RISC-V · FPGA · OPEN SOURCE</p>
<h1>A RISC-V computer you can read, build and play</h1>
<p class="lead"><strong>NandTier is an open-source RISC-V system-on-chip for small FPGA boards.</strong> It has its own RV32IM CPU, a boot ROM, execute-in-place SPI flash, an HDMI picture processor, an SD card and eight games, and it fits on a $25 Sipeed Tang Nano 9K. Everything is written in readable Verilog and C, and builds with open-source tools from one <code>make</code>.</p>
<p class="cta"><a class="btn" href="getting-started.html">Get started</a> <a class="btn ghost" href="https://github.com/NandTier/nandtier">View on GitHub</a></p>
</div>

<div class="pair"><img src="images/menu.gif" alt="The NandTier game menu on an HDMI screen" width="512" height="480"><img src="images/invaders.gif" alt="Alien Raid, one of the eight NandTier games" width="512" height="480"></div>

## What NandTier is

| | |
|---|---|
| **CPU** | RV32IM, multi-cycle, written from scratch: hardware multiply and divide, cycle and instruction counters |
| **Memory** | 8 MiB SPI flash, execute in place, with a 4 KiB read cache; 8 KiB SRAM; 8 KiB boot RAM |
| **Video** | 640x480 HDMI (DVI), an NES-style picture processing unit (tiles, sprites, scrolling) and an 80x25 text terminal |
| **I/O** | UART at 115200 baud, GPIO with 6 LEDs, SD card over SPI, an on-chip logic analyzer |
| **Boards** | Sipeed Tang Nano 9K (Gowin GW1NR-9C), Sipeed Tang Nano 20K (GW2AR-18C), Radiona ULX3S (Lattice ECP5) |
| **Tools** | Yosys, nextpnr, Apicula, openFPGALoader, Icarus Verilog, RISC-V GCC: all open source, installed by one script |
| **License** | Apache 2.0 |

## Who it is for

- **Students** who built a single-cycle RISC-V core and want to know what comes next: a bus, a boot ROM, flash, video, and software that runs on it.
- **Teachers** who need a complete, tested system that runs on a cheap board, with an offline installer for a whole lab.
- **Makers** who want to write their own games for their own computer.

## Read the documentation

- [Getting started](getting-started.html): install the tools, build, load the board, play.
- [RISC-V on the Tang Nano 9K](tang-nano-9k.html): boards, pins, clocks and programming.
- [SoC architecture](architecture.html): the bus, the address map and the FPGA resources.
- [The RV32IM CPU core](risc-v-cpu.html): stages, timing and what is supported.
- [Boot ROM and XIP flash](boot-rom-and-flash.html): from reset to your own firmware in the flash.
- [HDMI and the picture processor](hdmi-ppu.html): tiles, sprites and the text terminal.
- [Games and the game SDK](games.html): play the eight games, or write your own.
- [Open-source FPGA toolchain](open-source-fpga-toolchain.html): Yosys, nextpnr and Apicula for Gowin FPGAs.
- [Comparison](compare.html) with PicoRV32, NEORV32, VexRiscv and picotiny.
- [FAQ](faq.html)
