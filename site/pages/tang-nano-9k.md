---
slug: tang-nano-9k
title: RISC-V on the Tang Nano 9K, 20K and ULX3S
nav: Boards
description: Run a complete RISC-V SoC with HDMI on the Sipeed Tang Nano 9K (Gowin GW1NR-9C), Tang Nano 20K or Radiona ULX3S. Clocks, flash offsets, LEDs, programming with openFPGALoader, and porting to a new board.
---
# RISC-V on the Tang Nano 9K, 20K and ULX3S

**NandTier runs on three FPGA boards: the Sipeed Tang Nano 9K (the default), the Sipeed Tang Nano 20K and the Radiona ULX3S.** The boot ROM, the launcher, the games and the SD card pack are the same on all of them; only the bitstream differs.

| Board | FPGA | Clock in | HDMI | Firmware in flash at | `BOARD=` |
|---|---|---|---|---|---|
| Sipeed Tang Nano 9K | Gowin GW1NR-9C | 27 MHz | emulated LVDS | `0x000000` | `tangnano9k` |
| Sipeed Tang Nano 20K | Gowin GW2AR-18C | 27 MHz | true LVDS | `0x100000` | `tangnano20k` |
| Radiona ULX3S | Lattice ECP5 | 25 MHz | GPDI | `0x200000` | `ulx3s` |

On the Tang Nano 9K the bitstream lives inside the FPGA, so the whole SPI flash belongs to the firmware. On the other boards the bitstream sits at the start of the flash, and the hardware maps CPU address 0 to the flash from `FLASH_OFFSET` on, so the same firmware runs everywhere.

## Why the Tang Nano 9K

It costs about $25, has an HDMI connector, a USB-C port that carries both JTAG and a UART, a microSD slot, 6 LEDs and an SPI flash, and its Gowin GW1NR-9C is supported by the open-source Apicula project. That is everything a small computer needs.

## Clocks

```text
27 MHz crystal -> rPLL 124.875 MHz (HDMI bit clock / 2) -> CLKDIV /5 -> 24.975 MHz
```

The 24.975 MHz clock drives the CPU, the bus and the 640x480 pixel output at 59.46 Hz.

## Build and program for each board

```bash
make fpga BOARD=tangnano20k          # oss/build/tangnano20k/nandtier.fs
make fpga-load BOARD=tangnano20k     # into the FPGA, gone at power-off
make fpga-flash BOARD=tangnano20k    # into the configuration flash
make program BOARD=tangnano20k COMx=/dev/ttyUSB1
```

`fpga-flash` writes only the bitstream, so the launcher and the games stored above it stay.

## LEDs, buttons and the UART

- **LEDs:** GPIO pins 0-5 drive LEDs 1-6. They are active low: write 0 to light one.
- **Reset:** button S1. After reset the boot ROM listens on the UART for half a second, then starts the firmware.
- **UART:** 115200 baud over the same USB-C cable. On Windows, install the WinUSB driver on interface 0 (JTAG) with Zadig and leave interface 1, the UART, alone.

## Port NandTier to another board

Copy the closest `boards/<board>/` and change the PLL (about 25 MHz for the system and 5x for HDMI), the reset polarity and the pins, and set `FLASH_OFFSET` above the end of the bitstream on a 1 MiB boundary. Then add the board to `BOARDS` in `oss/Makefile`. Ports are welcome as [pull requests](https://github.com/NandTier/nandtier/blob/main/CONTRIBUTING.md).
