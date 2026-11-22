// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// The game menu on the HDMI screen: lists the games on the SD card, copies
// the chosen one into the flash cartridge slot and starts it. The list is
// also printed on the UART, where 1-9 picks a game directly.

#include "nandtier.h"
#include "ngame.h"
#include "art.h"
#include "console.h"
#include "loader.h"
#include "arcade.h"

#define LIST_ROW    7
#define STATUS_ROW  25
#define BAR_COL     6
#define BAR_LEN     20

#define PAL_WHITE   0
#define PAL_YELLOW  1
#define PAL_CYAN    2
#define PAL_GREY    3

static struct cart carts[NT_CART_MAX];
static int n_carts;

#define N_STARS 24
static struct star { int16_t x, y, speed, big; } stars[N_STARS];

static void status(const char *s, int pal)
{
	ng_fill(1, STATUS_ROW, 30, 2, 0, 0);
	ng_center(STATUS_ROW, s, pal);
}

static void progress(uint32_t done, uint32_t total)
{
	int n = done * BAR_LEN / total;
	for (int i = 0; i < BAR_LEN; i++)
		ng_tile(BAR_COL + i, STATUS_ROW + 1, i < n ? T_BAR_FULL : T_BAR_EMPTY, 0);
	if (done == total || (done & 7) == 0)
		print_char('.');
}

static void draw_frame(void)
{
	ng_fill(1, 0, 30, 1, T_FRAME_H, 0);
	ng_fill(1, 29, 30, 1, T_FRAME_H, 0);
	ng_fill(0, 1, 1, 28, T_FRAME_V, 0);
	ng_fill(31, 1, 1, 28, T_FRAME_V, 0);
	ng_tile(0, 0, T_FRAME_CORNER, 0);
	ng_tile(31, 0, T_FRAME_CORNER, 0);
	ng_tile(0, 29, T_FRAME_CORNER, 0);
	ng_tile(31, 29, T_FRAME_CORNER, 0);
	ng_center(2, "NANDTIER  ARCADE", PAL_YELLOW);
	ng_fill(6, 3, 20, 1, T_LINE, 0);
	ng_center(28, "UP/DOWN  START: PLAY  Q: EXIT", PAL_GREY);
}

static void draw_list(int sel)
{
	for (int i = 0; i < n_carts; i++) {
		int row = LIST_ROW + i * (n_carts > 8 ? 1 : 2);
		ng_number(7, row, i + 1, i + 1 >= 10 ? 2 : 1, i == sel ? PAL_YELLOW : PAL_GREY);
		ng_text(10, row, carts[i].name, i == sel ? PAL_CYAN : PAL_WHITE);
	}
}

static void stars_init(void)
{
	for (int i = 0; i < N_STARS; i++) {
		stars[i].x = ng_rand_range(256);
		stars[i].y = ng_rand_range(240) << 4;
		stars[i].speed = 4 + ng_rand_range(20);
		stars[i].big = stars[i].speed > 18;
	}
}

static void stars_draw(void)
{
	for (int i = 0; i < N_STARS; i++) {
		struct star *s = &stars[i];
		s->y += s->speed;
		if (s->y >= 240 << 4) {
			s->y = 0;
			s->x = ng_rand_range(256);
		}
		ng_sprite(s->x, s->y >> 4, s->big ? T_STAR_BIG : T_STAR_SMALL, 1, NG_BEHIND);
	}
}

static void print_list(void)
{
	print("Games on the SD card:\n");
	for (int i = 0; i < n_carts; i++) {
		print("  [");
		print_dec(i + 1);
		print("] ");
		print(carts[i].name);
		print("  (");
		print_dec(carts[i].size);
		print(" bytes)\n");
	}
	print("Choose on the HDMI screen (sw/gamepad.py) or press 1-");
	print_dec(n_carts < 9 ? n_carts : 9);
	if (n_carts >= 10)
		print(", 0 for 10");
	print(". Q goes back to the menu.\n");
}

// Copy game i into the flash (unless it is there) and start it.
static void launch(int i)
{
	const struct cart *c = &carts[i];

	print("Loading ");
	print(c->name);
	print(" from the SD card ");
	status("LOADING ...", PAL_YELLOW);
	int r = loader_install(c, progress);
	if (r < 0) {
		print(" failed: ");
		print(loader_error(r));
		print("\n");
		status(loader_error(r), PAL_YELLOW);
		return;
	}
	print(r == 1 ? "- in the flash already.\n" : " copied to the flash.\n");
	print("Starting ");
	print(c->name);
	print(". Q quits.\n");
	loader_start(i);
}

void arcade(int sel)
{
	ng_begin(art_chr, ART_TILES, art_palette);
	ng_seed(nt_cycles());
	draw_frame();
	stars_init();
	print("\nGame menu on the HDMI screen.\n");

	status("READING THE SD CARD", PAL_GREY);
	n_carts = loader_read_dir(carts, NT_CART_MAX);
	if (n_carts <= 0) {
		const char *msg = n_carts == 0 ? "NO GAMES ON THE SD CARD" : loader_error(n_carts);
		print(msg);
		print(". Write the games with: make program (see README).\nQ goes back.\n");
		status(msg, PAL_YELLOW);
		ng_center(STATUS_ROW + 1, "SEE README: MAKE PROGRAM", PAL_GREY);
		n_carts = 0;
	} else {
		status("", 0);
		print_list();
	}
	if (sel < 0 || sel >= n_carts)
		sel = 0;
	draw_list(sel);

	for (;;) {
		uint8_t p = ng_pressed();
		int key = ng_key();
		int old = sel;

		if (n_carts) {
			if (p & BTN_DOWN)
				sel = sel + 1 == n_carts ? 0 : sel + 1;
			if (p & BTN_UP)
				sel = sel == 0 ? n_carts - 1 : sel - 1;
			if (sel != old)
				draw_list(sel);
			// 1-9, and 0 for game 10
			int k = key == '0' ? 9 : key >= '1' && key <= '9' ? key - '1' : -1;
			if (k >= 0 && k < n_carts) {
				sel = k;
				draw_list(sel);
				launch(sel);
			} else if (p & (BTN_START | BTN_A)) {
				launch(sel);
			}
		}

		if (n_carts)        // pointer, nodding left and right
			ng_sprite(4 * 8 + ((ng_frame_count() >> 3) & 1), (LIST_ROW + sel * (n_carts > 8 ? 1 : 2)) * 8 - 4,
			          S_CURSOR, 0, NG_BIG);
		stars_draw();
		ng_frame();
		if (ng_quit())
			break;
	}

	for (int i = 0; i < 64; i++)
		PPU_REG(PPU_OAM + i * 4) = OAM_HIDDEN;
	PPU_REG(PPU_CTRL) = PPU_CTRL_TERM;
}
