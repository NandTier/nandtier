---
slug: faq
title: NandTier FAQ
nav: FAQ
description: Answers about NandTier: which boards it runs on, whether you need the Gowin IDE, what the RISC-V core supports, how much of the FPGA it uses, the licence, and how to write games for it.
---
# Frequently asked questions

### What is NandTier?
NandTier is an open-source RISC-V system-on-chip for small FPGA boards. It has an RV32IM CPU, a boot ROM, execute-in-place SPI flash, HDMI graphics, an SD card, and eight games, and it runs on the $25 Sipeed Tang Nano 9K.

### Which boards does it run on?
The Sipeed Tang Nano 9K (Gowin GW1NR-9C), the Sipeed Tang Nano 20K (Gowin GW2AR-18C) and the Radiona ULX3S (Lattice ECP5). See [Boards](tang-nano-9k.html).

### Do I need the Gowin IDE?
No. The bitstreams build with Yosys, nextpnr and Apicula. The Gowin IDE project is included as an alternative, and the whole-SoC simulation uses Gowin's primitive library.

### Does it work on Windows?
Yes. `setup\setup.bat` installs the tools on Windows, and macOS, Linux and WSL use `setup/setup.sh`.

### Which RISC-V instructions does the CPU support?
RV32I and the M extension (multiply and divide), FENCE as a no-op, and the cycle, time and instret counters. It has no interrupts and no compressed (C) instructions. See [the CPU](risc-v-cpu.html).

### How fast is it?
The CPU runs at 24.975 MHz. Most instructions take 4 cycles and loads and stores 7, plus wait cycles for slow memory. Code in the 4 KiB flash cache runs at full speed.

### How much of the Tang Nano 9K does it use?
About 61% of the logic, 38% of the registers and all 26 block RAMs, in the Gowin build.

### How do I put my own program on the board?
Write it in C, link it for flash address 0 like `fw/fw-flash`, and run `make program PROG_FILE=<your file>.v`. The boot ROM writes it into the flash over the USB cable. See [Boot ROM and XIP flash](boot-rom-and-flash.html).

### Can I write my own games?
Yes. A game is three files: a Makefile, an `art.py` with the pixels, and the C code using the `ngame` library. See [Games](games.html).

### Does it have sound?
Not yet. Audio output is one of the open ideas for contributors.

### What licence is it under?
Apache 2.0. Generated Gowin IP files are under Gowin's own terms; the `NOTICE` file lists them.

### Is there a course?
Yes. **Gates to Games** teaches NandTier from the first logic gate to the games, with a voiced film for every lesson. It is free at [nandtier.com](https://www.nandtier.com/).

### How can I help?
Report bugs, port it to a new board, add a game or a test. Read [CONTRIBUTING.md](https://github.com/NandTier/nandtier/blob/main/CONTRIBUTING.md) and ask in [Discussions](https://github.com/NandTier/nandtier/discussions).
