// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier Hopper: a side-scrolling platformer for the NandTier PPU.

#ifndef GAME_H
#define GAME_H

#include <stdint.h>

// Runs until the player quits (Q key; sw/gamepad.py sends it for Esc).
void game_run(void);

// CPU cycles of the slowest frame of the last game (logic and PPU updates;
// one frame lasts 419,580 cycles at 24.975 MHz / 59.5 Hz)
extern uint32_t game_slowest_frame;

// Controller buttons, as sent by sw/gamepad.py: 0x80 | buttons.
#define BTN_RIGHT  0x01
#define BTN_LEFT   0x02
#define BTN_DOWN   0x04
#define BTN_UP     0x08
#define BTN_START  0x10
#define BTN_B      0x20         // run
#define BTN_A      0x40         // jump

// Load the graphics pack from the SD card (assets/gen_assets.py makes it)
// straight into the PPU CHR and palette. Returns 0 if it was there.
int hal_load_sd_graphics(void);

#endif
