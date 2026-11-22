// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// PC model of the NandTier PPU and controller (ppu_model.c).
//
//   <program> <frames> <out prefix> [<frame>,...] [script] ...
//
//   script: "from-to:buttons;..." frames and button bits (fw/sdk/ngame.h),
//           e.g. "30-31:16;60-400:1" = press Start, then hold right;
//           button bit 8 (256) types 'q' instead
//   Writes <prefix>_<frame>.ppm (256 x 240) for each listed frame. After
//   <frames> frames it calls game_report() (which the game defines with
//   GAME_HOST) and stops.
//
//   NG_UART_IN=<file>   bytes for the UART, lines "<frame> <hex> <hex> ...":
//                       readable from that frame on, after the controller byte
//   NG_UART_OUT=<file>  everything the game sends on the UART

#ifndef PPU_MODEL_H
#define PPU_MODEL_H

void ppu_model_args(int argc, char **argv);
int  ppu_model_frame(void);
void game_report(void);

#endif
