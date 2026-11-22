// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Snake: steer the snake to the apples; every apple makes it longer and
// faster. Gold apples (every fifth) are worth more but do not wait long.
// Hitting a wall or the snake ends the game. Left alone, the title screen
// shows a demo game played by the computer.
//
// The field is the tile map: 30 x 26 cells at columns 1-30, rows 3-28.

#include "ngame.h"
#include "art.h"

#define FX0     1
#define FY0     3
#define FW      30
#define FH      26
#define CELL(c, r)  ((r) * 32 + (c))

enum { EMPTY, SNAKE, APPLE, GOLD, WALL };
enum { M_TITLE, M_PLAY, M_DEAD, M_OVER };

static uint8_t  occ[32 * 30];
static uint16_t body[1024];             // cells, a ring: body[head] is the head
static int      head, len, grow;
static int      dir, queued[2], n_queued;
static int      step_timer, apples, gold_cell, gold_timer;
static int      mode, timer, demo;
static uint32_t score, best;

static const int8_t DX[4] = {1, 0, -1, 0};     // right, up, left, down
static const int8_t DY[4] = {0, -1, 0, 1};

// --- drawing ----------------------------------------------------------------------

static void ground(int c, int r)
{
	occ[CELL(c, r)] = EMPTY;
	ng_tile(c, r, ((c * 5 + r * 3) ^ (c >> 1)) % 13 == 0 ? T_TUFT : 0, 0);
}

static void draw_head(void)
{
	int cell = body[head];
	static const uint16_t tiles[4] = {
		T_HEAD_R, T_HEAD_U, T_HEAD_R | NG_TILE_HFLIP, T_HEAD_U | NG_TILE_VFLIP
	};
	ng_tile(cell & 31, cell >> 5, tiles[dir], 0);
}

static void draw_hud(void)
{
	ng_text(1, 0, "SCORE", 3);
	ng_number(7, 0, score, 5, 0);
	ng_text(20, 0, "BEST", 3);
	ng_number(25, 0, best, 5, 0);
}

static void draw_field(void)
{
	ng_clear();
	ng_fill(0, 2, 32, 1, T_WALL, 0);
	ng_fill(0, 29, 32, 1, T_WALL, 0);
	ng_fill(0, 3, 1, FH, T_WALL, 0);
	ng_fill(31, 3, 1, FH, T_WALL, 0);
	for (int r = 0; r < 30; r++)
		for (int c = 0; c < 32; c++)
			occ[CELL(c, r)] = WALL;
	for (int r = FY0; r < FY0 + FH; r++)
		for (int c = FX0; c < FX0 + FW; c++)
			ground(c, r);
	draw_hud();
}

static void snake_colours(int dead)
{
	static const uint16_t live[3] = {0x2B2, 0x070, 0x8E6}, grey[3] = {0x999, 0x555, 0xCCC};
	for (int i = 0; i < 3; i++)
		ng_palette(3 + i, dead ? grey[i] : live[i]);
}

// --- apples ----------------------------------------------------------------------

static int free_cell(void)
{
	for (int tries = 0; tries < 200; tries++) {
		int cell = CELL(FX0 + ng_rand_range(FW), FY0 + ng_rand_range(FH));
		if (occ[cell] == EMPTY)
			return cell;
	}
	for (int cell = 0; cell < 32 * 30; cell++)
		if (occ[cell] == EMPTY)
			return cell;
	return -1;
}

static void place(int what)
{
	int cell = free_cell();
	if (cell < 0)
		return;
	occ[cell] = what;
	ng_tile(cell & 31, cell >> 5, what == GOLD ? T_GOLD : T_APPLE, 0);
	if (what == GOLD) {
		gold_cell = cell;
		gold_timer = 150;
	}
}

// --- game ------------------------------------------------------------------------

static void new_game(int is_demo)
{
	demo = is_demo;
	score = 0;
	apples = 0;
	gold_timer = 0;
	snake_colours(0);
	draw_field();
	head = 0;
	len = 0;
	for (int i = 0; i < 4; i++) {           // four cells, heading right
		head = (head + 1) & 1023;
		body[head] = CELL(FX0 + 6 + i, FY0 + FH / 2);
		occ[body[head]] = SNAKE;
		len++;
		ng_tile(body[head] & 31, body[head] >> 5, T_BODY, 0);
	}
	dir = 0;
	draw_head();
	n_queued = 0;
	grow = 0;
	step_timer = 0;
	place(APPLE);
	if (demo)
		ng_center(1, "DEMO - PRESS START", 1);
	mode = M_PLAY;
}

static void title(void)
{
	snake_colours(0);
	draw_field();
	ng_big_center(6, "SNAKE", 1, T_QUAD0);
	ng_center(13, "EAT THE APPLES, GROW LONG", 3);
	ng_center(14, "DO NOT BITE YOURSELF!", 3);
	ng_center(20, "ARROWS / WASD   STEER", 0);
	ng_center(21, "Q   BACK TO THE MENU", 0);
	ng_tile(8, 17, T_APPLE, 0);
	ng_tile(23, 17, T_GOLD, 0);
	mode = M_TITLE;
	timer = 0;
}

// demo player: the free direction that gets closest to an apple
static int ai_dir(void)
{
	int hc = body[head] & 31, hr = body[head] >> 5;
	int target = gold_timer ? gold_cell : -1;
	if (target < 0)
		for (int cell = 0; cell < 32 * 30 && target < 0; cell++)
			if (occ[cell] == APPLE)
				target = cell;
	int best_d = dir, best_cost = 1 << 30;
	for (int d = 0; d < 4; d++) {
		if (d == ((dir + 2) & 3))
			continue;
		int c = hc + DX[d], r = hr + DY[d];
		int t = occ[CELL(c, r)];
		if (t == WALL || t == SNAKE)
			continue;
		int cost = target < 0 ? 0 : (c > (target & 31) ? c - (target & 31) : (target & 31) - c) +
		                            (r > (target >> 5) ? r - (target >> 5) : (target >> 5) - r);
		// keep away from dead ends: count free neighbours
		int free = 0;
		for (int k = 0; k < 4; k++) {
			int n = occ[CELL(c + DX[k], r + DY[k])];
			free += n != WALL && n != SNAKE;
		}
		cost = cost * 4 + (free == 0 ? 1000 : 4 - free) + (d != dir);
		if (cost < best_cost) {
			best_cost = cost;
			best_d = d;
		}
	}
	return best_d;
}

static void steer(void)
{
	uint8_t p = ng_pressed();
	static const uint8_t btn[4] = {BTN_RIGHT, BTN_UP, BTN_LEFT, BTN_DOWN};
	for (int d = 0; d < 4; d++) {
		if (!(p & btn[d]) || n_queued == 2)
			continue;
		int last = n_queued ? queued[n_queued - 1] : dir;
		if (d != last && d != ((last + 2) & 3))
			queued[n_queued++] = d;
	}
}

static void die(void)
{
	mode = M_DEAD;
	timer = 0;
	if (!demo && score > best)
		best = score;
}

static void step(void)
{
	if (demo) {
		dir = ai_dir();
	} else if (n_queued) {
		dir = queued[0];
		queued[0] = queued[1];
		n_queued--;
	}

	int hc = body[head] & 31, hr = body[head] >> 5;
	int next = CELL(hc + DX[dir], hr + DY[dir]);
	int tail = body[(head - len + 1) & 1023];
	int t = occ[next];

	if (t == WALL || (t == SNAKE && (next != tail || grow))) {
		die();
		return;
	}
	if (t == APPLE) {
		score += 10;
		grow += 3;
		if (++apples % 5 == 0)
			place(GOLD);
		place(APPLE);
	} else if (t == GOLD) {
		score += 50;
		grow += 5;
		gold_timer = 0;
	}

	if (grow) {
		grow--;
		len++;
	} else {
		ground(tail & 31, tail >> 5);
	}
	ng_tile(hc, hr, T_BODY, 0);
	head = (head + 1) & 1023;
	body[head] = next;
	occ[next] = SNAKE;
	draw_head();
	draw_hud();
}

void game_main(void)
{
	ng_begin(art_chr, ART_TILES, art_palette);
	title();

	while (!ng_quit()) {
		uint8_t p = ng_pressed();
		timer++;

		switch (mode) {
		case M_TITLE:
			ng_center(17, (timer >> 5) & 1 ? "           " : "PRESS START", 1);
			if (p & (BTN_START | BTN_A)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_PLAY:
			if (demo && (p & (BTN_START | BTN_A))) {
				title();
				break;
			}
			steer();
			if (gold_timer && --gold_timer == 0 && occ[gold_cell] == GOLD)
				ground(gold_cell & 31, gold_cell >> 5);
			if (gold_timer && gold_timer < 40)    // blink before it goes
				ng_tile(gold_cell & 31, gold_cell >> 5, (gold_timer >> 2) & 1 ? T_GOLD : 0, 0);
			{
				int delay = 7 - len / 12;
				if (++step_timer >= (delay < 3 ? 3 : delay)) {
					step_timer = 0;
					step();
				}
			}
			break;

		case M_DEAD:
			snake_colours((timer >> 3) & 1);
			if (timer == 60) {
				snake_colours(1);
				ng_fill(9, 13, 14, 5, 0, 0);
				ng_center(14, "GAME OVER", 2);
				ng_center(16, "PRESS START", 0);
				mode = M_OVER;
				timer = 0;
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 120 : 1200))
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
	printf("mode=%d score=%u best=%u len=%d demo=%d\n", mode, (unsigned)score, (unsigned)best, len, demo);
}
#endif
