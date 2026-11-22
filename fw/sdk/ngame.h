// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// ngame: a small library for games on the NandTier PPU (hw/video/nt_ppu.v).
//
// The screen is 32 x 30 tiles (256 x 240 pixels) of a 64 x 32 tile map.
// Tiles 0x00-0x3F are the font (ASCII 0x20-0x5F, drawn in colour 15 of the
// palette); the art tool (fw/sdk/mkart.py) puts a game's 8 x 8 tiles from
// 0x40 and its 16 x 16 sprites from 0x80.
//
// A game's main loop:
//
//     ng_begin(art_chr, ART_TILES, art_palette);
//     for (;;) {
//         ... game logic: ng_buttons(), ng_pressed(), ng_tile(), ng_sprite() ...
//         ng_frame();                  // wait for the next frame, show the sprites
//         if (ng_quit()) break;
//     }
//
// Sprites are collected during a frame and shown from the next one on; the
// tile map changes at once.

#ifndef NGAME_H
#define NGAME_H

#include <stdint.h>
#include "game_hal.h"

// controller buttons, as sent by sw/gamepad.py (0x80 | buttons)
#define BTN_RIGHT  0x01
#define BTN_LEFT   0x02
#define BTN_DOWN   0x04
#define BTN_UP     0x08
#define BTN_START  0x10
#define BTN_B      0x20
#define BTN_A      0x40

// sprite flags
#define NG_HFLIP   0x1
#define NG_VFLIP   0x2
#define NG_BIG     0x4          // 16 x 16: tiles t, t+1, t+16, t+17
#define NG_BEHIND  0x8          // behind non-transparent background pixels

#define NG_COLS    32
#define NG_ROWS    30

// Set up the PPU: display off, empty tile map, no sprites, no scrolling,
// load `tiles` tiles of CHR (8 words each) and the 128 colours, then show
// background and sprites.
void ng_begin(const uint32_t *chr, int tiles, const uint16_t *palette);

// End the frame: wait for the next one, hand the sprites and the scroll
// position to the PPU, read the controller.
void ng_frame(void);

uint32_t ng_frame_count(void);
uint32_t ng_slowest_frame(void);        // CPU cycles of the busiest frame so far

uint8_t ng_buttons(void);               // buttons held now
uint8_t ng_pressed(void);               // buttons pressed since the last frame
int     ng_quit(void);                  // Q was pressed (Esc in sw/gamepad.py)
int     ng_key(void);                   // other key typed since the last frame, or 0

// tile map; OR NG_TILE_HFLIP / NG_TILE_VFLIP into a tile number to mirror it
#define NG_TILE_HFLIP 0x400
#define NG_TILE_VFLIP 0x800
void ng_tile(int col, int row, int tile, int pal);
void ng_fill(int col, int row, int w, int h, int tile, int pal);
void ng_clear(void);                    // whole map: tile 0 (blank)
void ng_text(int col, int row, const char *s, int pal);
void ng_center(int row, const char *s, int pal);
void ng_number(int col, int row, uint32_t v, int digits, int pal);

// Big letters, 3 x 4 tiles each, from the quarter-block tiles quad0.. that
// mkart.py makes with BIG_FONT = True (pass T_QUAD0). Up to 10 characters
// fit across the screen.
void ng_big_text(int col, int row, const char *s, int pal, int quad0);
void ng_big_center(int row, const char *s, int pal, int quad0);

void ng_scroll(int x, int y);           // from the next frame on
void ng_split(int line);                // lines above it are not scrolled

void ng_sprite(int x, int y, int tile, int pal, int flags);
void ng_palette(int index, uint16_t rgb);

// xorshift; ng_seed() with something the player did (e.g. the frame count
// when Start was pressed) makes every game different on the board
uint32_t ng_rand(void);
int      ng_rand_range(int n);          // 0..n-1, n <= 65536
void     ng_seed(uint32_t seed);

// Where the controller bytes come from (default: hal_key, the UART), and
// a function to call over and over while ng_frame() waits for the next
// frame. A game with its own traffic on the UART uses them to empty the
// UART's 16-byte receive FIFO in time and to pass on the controller bytes.
void ng_set_input(int (*get_byte)(void));
void ng_set_idle(void (*idle)(void));

// Leave the game: back to the launcher (on the PC build: stop).
void ng_exit(void) __attribute__((noreturn));

#endif
