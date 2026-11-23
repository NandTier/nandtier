---
slug: hdmi-ppu
title: HDMI graphics on an FPGA · tiles, sprites and a text terminal
nav: HDMI & PPU
description: NandTier drives 640x480 HDMI (DVI) from a Gowin FPGA and has an NES-style picture processing unit with a scrolling tile map, 64 sprites, palettes and an 80x25 text terminal, all in Verilog.
---
# HDMI and the picture processor

**NandTier draws its own picture: 640x480 over HDMI, from an NES-style picture processing unit (PPU) and a text terminal, all in Verilog.** The CPU never touches pixels; it writes tiles, sprites and scroll values, and the PPU draws every line in time.

## HDMI output

`hw/video/nt_video.v` produces 640x480 DVI at 59.46 Hz over the HDMI connector. TMDS encoding follows DVI 1.0; each lane, the clock included, goes through a Gowin OSER10 serialiser and an ELVDS output buffer. On the ECP5 the same picture goes through 10:1 shift registers with DDR outputs.

## The picture processing unit

The picture is 256 x 240 pixels, shown at 2x in the middle of the screen. The PPU lives at `0xC100_0000`:

| Offset | Contents |
|---|---|
| `0x0000` | CTRL: background, sprites, text terminal on/off |
| `0x0004` / `0x0008` | SCROLL_X / SCROLL_Y |
| `0x000C` | SPLIT: lines above it do not scroll (a fixed status bar) |
| `0x0010` | STATUS: vertical blank, frame counter |
| `0x0400` | palette: 128 colours, 12-bit RGB |
| `0x0800` | OAM: 64 sprites |
| `0x2000` | tile map: 64 x 32 tiles, two screens wide |
| `0x4000` | CHR: 256 tiles of 8 x 8 pixels, 4 bits per pixel |

- **Background:** a scrolling 64 x 32 tile map; each entry picks a tile, one of 4 palettes, and flips.
- **Sprites:** 64 of them, 8x8 or 16x16, with palette, flips and a behind-the-background flag; up to 16 per line.
- **Timing:** each line is drawn into a line buffer while the previous one is shown. That gives 1600 cycles per line; 16 large sprites need about 820.

The exact bit layouts are in the header of `nt_ppu.v` and as C macros in `fw/include/nandtier.h`.

## The text terminal

`nt_text_term` lays an 80 x 25 text screen over the picture, with an 8 x 16 font generated from `hw/video/gen_font.py`. Every byte the CPU writes to the UART also appears here, so the board has a console on the HDMI screen without any software driver. It understands LF, CR, backspace, tab and clear-screen.

## Tested against a model

`make -C test video` checks the TMDS encoder and the video timing, renders three PPU frames and compares them with a reference model, and rebuilds the ECP5 serialiser's words from its bit stream.
