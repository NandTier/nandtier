// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0

#include "ngame.h"

#ifdef GAME_HOST
void host_exit(void) __attribute__((noreturn));     // test/host/ng_host.c
#else
#include "cart.h"
#endif

static uint32_t oam[64];
static int      n_sprites, shown_sprites;
static int      scroll_x, scroll_y;
static uint32_t frames, frame_start, slowest;
static uint32_t rng = 0x2545F491;
static int    (*input_byte)(void) = hal_key;
static void   (*idle_fn)(void);

void ng_set_input(int (*get_byte)(void)) { input_byte = get_byte ? get_byte : hal_key; }
void ng_set_idle(void (*idle)(void))     { idle_fn = idle; }

// --- input ------------------------------------------------------------------------
//
// sw/gamepad.py sends 0x80 | buttons whenever they change. Plain keys from
// a serial terminal hold a button for 20 frames, which the terminal's
// auto-repeat keeps alive.

static uint8_t pad, pad_link, held, last_held;
static uint8_t key_hold[7];
static int     esc_state, quit, typed;

static void key_press(int bit)
{
	key_hold[bit] = 20;
}

static void poll_input(void)
{
	int k;
	typed = 0;
	while ((k = input_byte()) >= 0) {
		if (k & 0x80) {
			pad = k & 0x7F;
			pad_link = 1;
			continue;
		}
		if (esc_state == 1) { esc_state = k == '[' ? 2 : 0; continue; }
		if (esc_state == 2) {
			esc_state = 0;
			if (k == 'A') key_press(3);
			if (k == 'B') key_press(2);
			if (k == 'C') key_press(0);
			if (k == 'D') key_press(1);
			continue;
		}
		switch (k) {
		case 0x1B: esc_state = 1; break;
		case 'd': case 'D': key_press(0); break;
		case 'a': case 'A': key_press(1); break;
		case 's': case 'S': key_press(2); break;
		case 'w': case 'W': key_press(3); break;
		case '\r': case '\n': key_press(4); break;
		case 'j': case 'J': case 'z': case 'Z': key_press(5); break;
		case ' ': case 'k': case 'K': case 'x': case 'X': key_press(6); break;
		case 'q': case 'Q': quit = 1; break;
		default: typed = k; break;
		}
	}
	last_held = held;
	held = pad_link ? pad : 0;
	for (int i = 0; i < 7; i++) {
		if (key_hold[i]) {
			held |= 1 << i;
			key_hold[i]--;
		}
	}
}

uint8_t ng_buttons(void) { return held; }
uint8_t ng_pressed(void) { return held & ~last_held; }
int     ng_quit(void)    { return quit; }
int     ng_key(void)     { return typed; }

// --- frames -----------------------------------------------------------------------

void ng_begin(const uint32_t *chr, int tiles, const uint16_t *palette)
{
	hal_ppu_write(PPU_CTRL, 0);
	hal_ppu_write(PPU_SPLIT, 0);
	hal_ppu_write(PPU_SCROLL_X, 0);
	hal_ppu_write(PPU_SCROLL_Y, 0);
	scroll_x = scroll_y = 0;
	for (int i = 0; i < tiles * 8; i++)
		hal_ppu_write(PPU_CHR + i * 4, chr[i]);
	for (int i = 0; i < 128; i++)
		hal_ppu_write(PPU_PALETTE + i * 4, palette[i]);
	for (int i = 0; i < 64; i++)
		hal_ppu_write(PPU_OAM + i * 4, OAM_HIDDEN);
	n_sprites = shown_sprites = 0;
	ng_clear();
	quit = 0;
	poll_input();
	last_held = held;
	hal_ppu_write(PPU_CTRL, PPU_CTRL_BG | PPU_CTRL_SPR);
	frame_start = hal_cycles();
}

void ng_frame(void)
{
	uint32_t busy = hal_cycles() - frame_start;
	if (busy > slowest)
		slowest = busy;

	uint32_t f = hal_ppu_read(PPU_STATUS) >> 16;
	while ((hal_ppu_read(PPU_STATUS) >> 16) == f)
		if (idle_fn)
			idle_fn();
	frame_start = hal_cycles();
	frames++;

	for (int i = 0; i < n_sprites; i++)
		hal_ppu_write(PPU_OAM + i * 4, oam[i]);
	for (int i = n_sprites; i < shown_sprites; i++)
		hal_ppu_write(PPU_OAM + i * 4, OAM_HIDDEN);
	shown_sprites = n_sprites;
	n_sprites = 0;
	hal_ppu_write(PPU_SCROLL_X, scroll_x);
	hal_ppu_write(PPU_SCROLL_Y, scroll_y);

	poll_input();
}

uint32_t ng_frame_count(void)   { return frames; }
uint32_t ng_slowest_frame(void) { return slowest; }

// --- tile map -------------------------------------------------------------------

void ng_tile(int col, int row, int tile, int pal)
{
	hal_ppu_write(PPU_NAMETAB + (((row & 31) << 6) + (col & 63)) * 4, tile | pal << 8);
}

void ng_fill(int col, int row, int w, int h, int tile, int pal)
{
	for (int r = row; r < row + h; r++)
		for (int c = col; c < col + w; c++)
			ng_tile(c, r, tile, pal);
}

void ng_clear(void)
{
	for (int i = 0; i < 64 * 32; i++)
		hal_ppu_write(PPU_NAMETAB + i * 4, 0);
}

void ng_text(int col, int row, const char *s, int pal)
{
	for (; *s; s++, col++) {
		int c = *s;
		if (c >= 'a' && c <= 'z')
			c -= 'a' - 'A';
		ng_tile(col, row, c >= 0x20 && c < 0x60 ? c - 0x20 : 0, pal);
	}
}

void ng_center(int row, const char *s, int pal)
{
	int len = 0;
	while (s[len])
		len++;
	ng_text((NG_COLS - len) / 2, row, s, pal);
}

void ng_number(int col, int row, uint32_t v, int digits, int pal)
{
	for (int i = digits - 1; i >= 0; i--) {
		ng_tile(col + i, row, '0' - 0x20 + v % 10, pal);
		v /= 10;
	}
}

extern const uint8_t art_font[64][8];      // from mkart.py

void ng_big_text(int col, int row, const char *s, int pal, int quad0)
{
	for (; *s; s++, col += 3) {
		int c = *s;
		if (c >= 'a' && c <= 'z')
			c -= 'a' - 'A';
		const uint8_t *g = art_font[c >= 0x20 && c < 0x60 ? c - 0x20 : 0];
		for (int ty = 0; ty < 4; ty++) {
			for (int tx = 0; tx < 3; tx++) {
				// pixels 2tx, 2tx+1 of rows 2ty, 2ty+1 (pixel 5 is the gap)
				int q = 0;
				for (int k = 0; k < 4; k++) {
					int px = 2 * tx + (k & 1), py = 2 * ty + (k >> 1);
					if (px < 5 && (g[py] >> (4 - px)) & 1)
						q |= 1 << k;
				}
				ng_tile(col + tx, row + ty, q ? quad0 + q : 0, pal);
			}
		}
	}
}

void ng_big_center(int row, const char *s, int pal, int quad0)
{
	int len = 0;
	while (s[len])
		len++;
	ng_big_text((NG_COLS - len * 3) / 2, row, s, pal, quad0);
}

void ng_scroll(int x, int y)
{
	scroll_x = x & 511;
	scroll_y = y & 255;
}

void ng_split(int line)
{
	hal_ppu_write(PPU_SPLIT, line);
}

// --- sprites, colours -------------------------------------------------------------

void ng_sprite(int x, int y, int tile, int pal, int flags)
{
	if (n_sprites == 64 || y <= -16 || y >= 240 || x <= -16 || x >= 256)
		return;
	if (y < 0)              // the PPU cannot place a sprite above the screen
		return;
	oam[n_sprites++] = OAM_ENTRY(y, x, tile, pal, flags & NG_HFLIP ? 1 : 0,
	                             flags & NG_VFLIP ? 1 : 0, flags & NG_BIG ? 1 : 0,
	                             flags & NG_BEHIND ? 1 : 0);
}

void ng_palette(int index, uint16_t rgb)
{
	hal_ppu_write(PPU_PALETTE + index * 4, rgb);
}

// --- random numbers -----------------------------------------------------------------

uint32_t ng_rand(void)
{
	rng ^= rng << 13;
	rng ^= rng >> 17;
	rng ^= rng << 5;
	return rng;
}

int ng_rand_range(int n)
{
	return (int)(((ng_rand() >> 16) * (uint32_t)n) >> 16);
}

void ng_seed(uint32_t seed)
{
	rng = seed ? seed : 0x2545F491;
}

// --- leaving -----------------------------------------------------------------------

void ng_exit(void)
{
	for (int i = 0; i < 64; i++)
		hal_ppu_write(PPU_OAM + i * 4, OAM_HIDDEN);
#ifdef GAME_HOST
	host_exit();
#else
	cart_exit(slowest);
#endif
}
