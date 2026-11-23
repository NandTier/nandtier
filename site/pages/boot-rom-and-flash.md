---
slug: boot-rom-and-flash
title: RISC-V boot ROM and execute-in-place (XIP) SPI flash on an FPGA
nav: Boot & flash
description: How NandTier boots: the reset vector in boot RAM, start.S, a half-second UART window, a command loop that programs the SPI flash, and execute-in-place with a 4 KiB cache. No programmer hardware needed.
---
# Boot ROM and XIP flash

**NandTier needs no programmer hardware: its own boot ROM writes new firmware into the SPI flash over the UART.** At reset the CPU starts in the boot ROM. For half a second it listens for the PC; if nothing comes, it jumps to the firmware, which runs straight from the flash (execute in place).

## From reset to your program

1. **Reset:** the program counter is loaded with `0x8000_0000`, the start of the boot RAM. The boot ROM image is part of the bitstream: it is loaded into the block RAM at configuration.
2. **`start.S`:** sets the stack pointer to the top of the boot RAM, clears `.bss`, and calls `main`.
3. **`main`:** sets the UART to 115200 baud and watches it for half a second.
4. **No byte arrives:** `main` jumps to address `0x0000_0000`, and the CPU fetches the firmware from the flash.
5. **`0x55` arrives:** the boot ROM answers `0x56` and enters `serve()`, its command loop.

## The programmer commands

`sw/nandtier-programmer.py` on the PC sends one command byte at a time; the boot ROM does the work.

| Byte | Command |
|---|---|
| `0x10` | load up to 256 bytes into the page buffer in boot RAM, answer a checksum |
| `0x30` | erase a 4 KiB flash sector |
| `0x40` | program a 256-byte flash page from the buffer |
| `0x60` / `0x62` | initialise the SD card / write one 512-byte SD block |
| `0xF0` | restart the boot ROM |

`make program` erases each sector, sends each page, checks each checksum (and resends a page up to three times), writes the game pack to the SD card, and finally sends `0xF0`. The boot ROM restarts, no ping comes, and the new firmware runs.

## Two flash modes

The flash controller `nt_spi_flash` owns the four flash wires and has two modes, chosen by bit 31 (`XIP_EN`) of its config register at `0x8100_0000`:

- **XIP on (at reset):** the read engine sends read commands by itself, so the flash looks like plain memory at address 0. Straight-line code streams without new commands, and optional dual I/O and continuous read modes make it faster.
- **XIP off:** the pins go to a bit-bang register, and software drives every clock edge. The boot ROM uses this to send write-enable, erase, program and status commands.

Switching is safe by design: clearing `XIP_EN` first takes the flash out of continuous read mode, and only then hands the pins over; config writes wait meanwhile. The code that does the switching, `flash_io()`, runs from boot RAM, so the CPU never fetches from the flash while it is busy. Firmware can call it too, at the fixed address `0x8000_0054`.

## The read cache

`nt_flash_cache` sits between the bus and the flash: 4 KiB, direct mapped, 16-byte lines. A hit answers in one cycle, like the SRAM; a miss reads the whole line from the flash. The cache empties itself whenever the flash controller re-initialises, so after programming it never returns stale code.

## Watch it

The NandTier films follow this path line by line, from the reset button through `start.S` to `make program` and a new LED-blink program in the flash. They are part of the [Gates to Games](https://www.nandtier.com/) course.
