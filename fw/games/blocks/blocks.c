// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Block Drop: falling blocks. Fill whole rows to clear them; the game gets
// faster every 10 rows. The pieces come in shuffled bags of seven, a ghost
// shows where the piece will land.
//
//   left/right  move            A  turn clockwise     up    drop
//   down        drop faster     B  turn back          Start pause
//
// The well and everything else are background tiles (column 11-20, rows
// 6-25 of the tile map for the 10 x 20 well).

#include "ngame.h"
#include "art.h"

#define WW      10
#define WH      20
#define WX      11
#define WY      6

enum { M_TITLE, M_PLAY, M_CLEAR, M_TOPOUT, M_OVER, M_PAUSE };

static uint8_t  well[WH][WW];           // 0 empty, 1-7 piece colour
static uint8_t  shapes[7][4][4];        // [piece][rotation][cell] = y << 2 | x
static int      piece, rot, px, py;     // falling piece
static int      ghost_y;
static int      next, bag[7], bag_left;
static int      fall_timer, lock_timer, das_timer;
static uint8_t  full_rows[4];
static int      n_full;
static uint32_t score, best;
static int      lines, level;
static int      mode, timer, demo;
static int      ai_rot, ai_x;           // demo player's target

static const uint8_t SPAWN[7][4] = {    // rotation 0 as y << 2 | x
	{4, 5, 6, 7},           // I
	{1, 2, 5, 6},           // O
	{1, 4, 5, 6},           // T
	{1, 2, 4, 5},           // S
	{0, 1, 5, 6},           // Z
	{0, 4, 5, 6},           // J
	{2, 4, 5, 6},           // L
};
static const uint8_t GRAVITY[] = {48, 43, 38, 33, 28, 23, 18, 13, 8, 6, 5, 5, 5, 4, 4, 4, 3, 3, 3, 2};
static const uint16_t LINE_PTS[5] = {0, 40, 100, 300, 1200};

// --- pieces -----------------------------------------------------------------------

static void make_shapes(void)
{
	for (int p = 0; p < 7; p++) {
		int n = p == 0 ? 4 : 3;         // turns about the middle of a 4 x 4 or 3 x 3 box
		for (int k = 0; k < 4; k++)
			shapes[p][0][k] = SPAWN[p][k];
		for (int r = 1; r < 4; r++)
			for (int k = 0; k < 4; k++) {
				int c = shapes[p][r - 1][k], x = c & 3, y = c >> 2;
				shapes[p][r][k] = p == 1 ? c : x << 2 | (n - 1 - y);    // O does not turn
			}
	}
}

static int collides(int p, int r, int x, int y)
{
	for (int k = 0; k < 4; k++) {
		int cx = x + (shapes[p][r][k] & 3), cy = y + (shapes[p][r][k] >> 2);
		if (cx < 0 || cx >= WW || cy >= WH)
			return 1;
		if (cy >= 0 && well[cy][cx])
			return 1;
	}
	return 0;
}

static int take_from_bag(void)
{
	if (bag_left == 0) {
		for (int i = 0; i < 7; i++)
			bag[i] = i;
		for (int i = 6; i > 0; i--) {
			int j = ng_rand_range(i + 1), t = bag[i];
			bag[i] = bag[j];
			bag[j] = t;
		}
		bag_left = 7;
	}
	return bag[--bag_left];
}

// --- drawing ------------------------------------------------------------------------

static void draw_cell(int x, int y)
{
	if (y < 0)
		return;
	int c = well[y][x];
	ng_tile(WX + x, WY + y, c ? T_CELL0 + c - 1 : T_DOTS, c ? 0 : 1);
}

static void draw_well(void)
{
	for (int y = 0; y < WH; y++)
		for (int x = 0; x < WW; x++)
			draw_cell(x, y);
}

// the falling piece and its ghost: on, or back to what the well shows
static void draw_piece(int on)
{
	for (int k = 0; k < 4; k++) {
		int cx = px + (shapes[piece][rot][k] & 3);
		int gy = ghost_y + (shapes[piece][rot][k] >> 2);
		if (on) {
			if (gy >= 0)
				ng_tile(WX + cx, WY + gy, T_GHOST, 1);
		} else {
			draw_cell(cx, gy);
		}
	}
	for (int k = 0; k < 4; k++) {
		int cx = px + (shapes[piece][rot][k] & 3), cy = py + (shapes[piece][rot][k] >> 2);
		if (on) {
			if (cy >= 0)
				ng_tile(WX + cx, WY + cy, T_CELL0 + piece, 0);
		} else {
			draw_cell(cx, cy);
		}
	}
}

static void draw_next(void)
{
	ng_fill(24, 9, 4, 2, 0, 0);
	for (int k = 0; k < 4; k++)
		ng_tile(24 + (SPAWN[next][k] & 3), 9 + (SPAWN[next][k] >> 2) - (next == 0), T_CELL0 + next, 0);
}

static void draw_hud(void)
{
	ng_number(1, 8, score, 7, 3);
	ng_number(3, 12, lines, 4, 3);
	ng_number(5, 16, level, 2, 3);
	ng_number(23, 21, best, 7, 3);
}

static void draw_frame(void)
{
	ng_clear();
	ng_fill(WX - 1, WY - 1, 1, WH + 2, T_WALL, 1);
	ng_fill(WX + WW, WY - 1, 1, WH + 2, T_WALL, 1);
	ng_fill(WX, WY + WH, WW, 1, T_WALL, 1);
	ng_text(1, 7, "SCORE", 2);
	ng_text(1, 11, "LINES", 2);
	ng_text(1, 15, "LEVEL", 2);
	ng_text(23, 7, "NEXT", 2);
	ng_text(23, 20, "BEST", 2);
	ng_center(2, "BLOCK DROP", 1);
}

// --- moving -----------------------------------------------------------------------------

static void update_ghost(void)
{
	ghost_y = py;
	while (!collides(piece, rot, px, ghost_y + 1))
		ghost_y++;
}

// try to put the piece at (r, x, y); returns 1 if it moved
static int try_move(int r, int x, int y)
{
	if (collides(piece, r, x, y))
		return 0;
	draw_piece(0);
	rot = r;
	px = x;
	py = y;
	update_ghost();
	draw_piece(1);
	return 1;
}

static int turn(int dir)
{
	static const int8_t KICKS[6][2] = {{0, 0}, {-1, 0}, {1, 0}, {0, -1}, {-2, 0}, {2, 0}};
	int r = (rot + dir) & 3;
	for (int i = 0; i < 6; i++)
		if (try_move(r, px + KICKS[i][0], py + KICKS[i][1])) {
			lock_timer = 0;
			return 1;
		}
	return 0;
}

static void choose_ai_target(void);

static void spawn(void)
{
	piece = next;
	next = take_from_bag();
	rot = 0;
	px = 3;
	py = piece == 0 ? -1 : 0;
	fall_timer = 0;
	lock_timer = 0;
	draw_next();
	if (collides(piece, rot, px, py)) {
		mode = M_TOPOUT;
		timer = 0;
		if (!demo && score > best)
			best = score;
		return;
	}
	update_ghost();
	draw_piece(1);
	if (demo)
		choose_ai_target();
}

static void lock_piece(void)
{
	for (int k = 0; k < 4; k++) {
		int cx = px + (shapes[piece][rot][k] & 3), cy = py + (shapes[piece][rot][k] >> 2);
		if (cy >= 0)
			well[cy][cx] = piece + 1;
	}
	n_full = 0;
	for (int y = 0; y < WH; y++) {
		int n = 0;
		for (int x = 0; x < WW; x++)
			n += well[y][x] != 0;
		if (n == WW)
			full_rows[n_full++] = y;
	}
	if (n_full) {
		mode = M_CLEAR;
		timer = 0;
	} else {
		spawn();
	}
}

static void remove_full_rows(void)
{
	for (int i = 0; i < n_full; i++) {
		for (int y = full_rows[i]; y > 0; y--)
			for (int x = 0; x < WW; x++)
				well[y][x] = well[y - 1][x];
		for (int x = 0; x < WW; x++)
			well[0][x] = 0;
	}
	score += LINE_PTS[n_full] * (level + 1);
	lines += n_full;
	level = lines / 10;
	if (level > 19)
		level = 19;
	draw_well();
	draw_hud();
}

// --- demo player -------------------------------------------------------------------------
//
// Tries every turn and column, drops the piece there and rates the well:
// fewer holes, lower and flatter is better, full rows are good.

static int rate_well(void)
{
	int height[WW], holes = 0, total = 0, bumps = 0, full = 0;
	for (int x = 0; x < WW; x++) {
		height[x] = 0;
		for (int y = 0; y < WH; y++)
			if (well[y][x]) {
				height[x] = WH - y;
				for (int yy = y + 1; yy < WH; yy++)
					holes += !well[yy][x];
				break;
			}
		total += height[x];
		if (x)
			bumps += height[x] > height[x - 1] ? height[x] - height[x - 1] : height[x - 1] - height[x];
	}
	for (int y = 0; y < WH; y++) {
		int n = 0;
		for (int x = 0; x < WW; x++)
			n += well[y][x] != 0;
		full += n == WW;
	}
	return full * 76 - total * 51 - holes * 356 - bumps * 18;
}

static void choose_ai_target(void)
{
	int best_rate = -0x40000000;
	ai_rot = 0;
	ai_x = px;
	for (int r = 0; r < 4; r++) {
		for (int x = -2; x < WW; x++) {
			if (collides(piece, r, x, py))
				continue;
			int y = py;
			while (!collides(piece, r, x, y + 1))
				y++;
			uint8_t saved[4];
			for (int k = 0; k < 4; k++) {
				int cx = x + (shapes[piece][r][k] & 3), cy = y + (shapes[piece][r][k] >> 2);
				saved[k] = cy >= 0 ? well[cy][cx] : 0;
				if (cy >= 0)
					well[cy][cx] = 8;
			}
			int rate = rate_well();
			for (int k = 0; k < 4; k++) {
				int cx = x + (shapes[piece][r][k] & 3), cy = y + (shapes[piece][r][k] >> 2);
				if (cy >= 0)
					well[cy][cx] = saved[k];
			}
			if (rate > best_rate) {
				best_rate = rate;
				ai_rot = r;
				ai_x = x;
			}
		}
	}
}

// controller presses the demo player makes this frame
static uint8_t ai_buttons(void)
{
	if (timer & 3)
		return 0;
	if (rot != ai_rot)
		return BTN_A;
	if (px > ai_x)
		return BTN_LEFT;
	if (px < ai_x)
		return BTN_RIGHT;
	return BTN_UP;
}

// --- game ---------------------------------------------------------------------------------

static void play(uint8_t b, uint8_t p)
{
	if (demo) {
		p = ai_buttons();
		b = p;
	}
	if (p & BTN_START) {
		mode = M_PAUSE;
		ng_fill(WX, 14, WW, 1, 0, 0);
		ng_text(WX + 2, 14, "PAUSE", 1);
		return;
	}

	// sideways: once, then repeated while held
	int dx = 0;
	if (p & (BTN_LEFT | BTN_RIGHT)) {
		dx = p & BTN_LEFT ? -1 : 1;
		das_timer = 0;
	} else if (b & (BTN_LEFT | BTN_RIGHT)) {
		if (++das_timer >= 12 && ((das_timer - 12) % 3) == 0)
			dx = b & BTN_LEFT ? -1 : 1;
	}
	if (dx && try_move(rot, px + dx, py))
		lock_timer = 0;

	if (p & BTN_A)
		turn(1);
	if (p & BTN_B)
		turn(3);

	if (p & BTN_UP) {                       // drop
		score += 2 * (ghost_y - py);
		try_move(rot, px, ghost_y);
		lock_piece();
		draw_hud();
		return;
	}

	int delay = b & BTN_DOWN ? 2 : GRAVITY[level];
	if (++fall_timer >= delay) {
		fall_timer = 0;
		if (try_move(rot, px, py + 1)) {
			if (b & BTN_DOWN) {
				score++;
				draw_hud();
			}
		}
	}
	if (collides(piece, rot, px, py + 1)) {
		if (++lock_timer >= 30)
			lock_piece();
	} else {
		lock_timer = 0;
	}
}

static void new_game(int is_demo)
{
	demo = is_demo;
	score = 0;
	lines = 0;
	level = 0;
	for (int y = 0; y < WH; y++)
		for (int x = 0; x < WW; x++)
			well[y][x] = 0;
	bag_left = 0;
	draw_frame();
	draw_well();
	draw_hud();
	if (demo)
		ng_center(28, "DEMO - PRESS START", 1);
	next = take_from_bag();
	mode = M_PLAY;
	timer = 0;
	spawn();
}

static void title(void)
{
	ng_clear();
	ng_big_center(4, "BLOCK", 1, T_QUAD0);
	ng_big_center(9, "DROP", 2, T_QUAD0);
	for (int p = 0; p < 7; p++)
		for (int k = 0; k < 4; k++)
			ng_tile(2 + p * 4 + (SPAWN[p][k] & 3), 15 + (SPAWN[p][k] >> 2), T_CELL0 + p, 0);
	ng_center(22, "LEFT/RIGHT MOVE   DOWN FASTER", 3);
	ng_center(23, "A/B TURN   UP DROP", 3);
	ng_center(24, "START PAUSE   Q MENU", 3);
	ng_text(1, 0, "BEST", 3);
	ng_number(6, 0, best, 7, 1);
	mode = M_TITLE;
	timer = 0;
}

void game_main(void)
{
	make_shapes();
	ng_begin(art_chr, ART_TILES, art_palette);
	title();

	while (!ng_quit()) {
		uint8_t b = ng_buttons(), p = ng_pressed();
		timer++;
		if (demo && mode != M_TITLE && (p & (BTN_START | BTN_A))) {
			demo = 0;
			title();
			ng_frame();
			continue;
		}

		switch (mode) {
		case M_TITLE:
			ng_center(19, (timer >> 5) & 1 ? "           " : "PRESS START", 1);
			if (p & (BTN_START | BTN_A)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_PLAY:
			play(b, p);
			break;

		case M_PAUSE:
			if (p & BTN_START) {
				ng_fill(WX, 14, WW, 1, 0, 0);
				draw_well();
				draw_piece(1);
				mode = M_PLAY;
			}
			break;

		case M_CLEAR:
			for (int i = 0; i < n_full; i++)
				for (int x = 0; x < WW; x++) {
					if ((timer >> 2) & 1)
						ng_tile(WX + x, WY + full_rows[i], T_FLASH, 1);
					else
						draw_cell(x, full_rows[i]);
				}
			if (timer == 16) {
				remove_full_rows();
				mode = M_PLAY;
				spawn();
			}
			break;

		case M_TOPOUT:                      // grey the well from the bottom up
			if (timer <= WH) {
				for (int x = 0; x < WW; x++)
					ng_tile(WX + x, WY + WH - timer, T_WALL, 3);
			} else {
				ng_fill(WX, 13, WW, 3, 0, 0);
				ng_text(WX + 1, 14, "GAME OVER", 1);
				draw_hud();
				mode = M_OVER;
				timer = 0;
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 90 : 1200))
				title();
			break;
		}
		ng_frame();
	}
}

#ifdef GAME_HOST
#include <stdio.h>
void game_report(void)
{
	printf("mode=%d score=%u best=%u lines=%d level=%d demo=%d\n", mode, (unsigned)score,
	       (unsigned)best, lines, level, demo);
}
#endif
