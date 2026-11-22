// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Flappy Chip: tap to flap through the gaps between the pipes. One point
// per pipe; the world speeds up as the score grows.
//
// The world scrolls sideways through the PPU's two-screen tile map: each
// new column is drawn just before it scrolls into view. Rows 0-1 (score)
// are above the PPU split line and stay put. The bird is a sprite.

#include "ngame.h"
#include "art.h"

#define BIRD_X      64              // on the screen
#define SKY_TOP     16              // pixels
#define GROUND_ROW  26
#define PIPE_FIRST  40              // world column of the first pipe
#define PIPE_EVERY  10              // columns
#define GAP         7               // rows
#define N_GAPS      16

enum { M_TITLE, M_READY, M_PLAY, M_FALL, M_OVER };

static int32_t  world_x;                // scroll position, 1/256 pixel
static int      drawn_to;               // next world column to draw
static uint8_t  gap_top[N_GAPS];        // first open row of pipe i (i % N_GAPS)
static int32_t  bird_y, bird_vy;        // 1/256 pixel
static int      flap_anim;
static int      next_pipe;              // pipe the bird has not passed yet
static uint32_t score, best;
static int      mode, timer, demo;

// --- world ------------------------------------------------------------------------------

static int pipe_at(int col)             // pipe number at a world column, or -1
{
	if (col < PIPE_FIRST || (col - PIPE_FIRST) % PIPE_EVERY >= 2)
		return -1;
	return (col - PIPE_FIRST) / PIPE_EVERY;
}

static void draw_column(int col)
{
	int c = col & 63, pipe = pipe_at(col), left = pipe >= 0 && (col - PIPE_FIRST) % PIPE_EVERY == 0;
	if (left)                       // a new pipe: choose its gap
		gap_top[pipe % N_GAPS] = 4 + ng_rand_range(GROUND_ROW - GAP - 6);
	int top = pipe >= 0 ? gap_top[pipe % N_GAPS] : 0;

	for (int r = 2; r < GROUND_ROW; r++) {
		int tile = 0;
		if (pipe >= 0 && (r < top || r >= top + GAP)) {
			int cap = r == top - 1 || r == top + GAP;
			tile = left ? (cap ? T_CAP_L : T_PIPE_L) : (cap ? T_CAP_R : T_PIPE_R);
		} else {
			// scenery: clouds (two tiles) high up, bushes on the ground
			int cloud = col / 9, part = col % 9;
			if (part < 2 && r == 4 + (cloud * 5) % 7)
				tile = part ? T_CLOUD_R : T_CLOUD_L;
			else if (r == GROUND_ROW - 1 && (col * 7 + (col >> 3)) % 5 == 0)
				tile = T_BUSH;
		}
		ng_tile(c, r, tile, 0);
	}
	ng_tile(c, GROUND_ROW, T_GRASS, 0);
	for (int r = GROUND_ROW + 1; r < 32; r++)
		ng_tile(c, r, T_DIRT, 0);
}

static void draw_ahead(void)
{
	while (drawn_to <= (world_x >> 11) + 33)
		draw_column(drawn_to++);
}

static int solid(int wx, int y)         // world pixel
{
	if (y >= GROUND_ROW * 8)
		return 1;
	int pipe = pipe_at(wx >> 3);
	if (pipe < 0)
		return 0;
	int r = y >> 3, top = gap_top[pipe % N_GAPS];
	return r < top || r >= top + GAP;
}

static void draw_score(void)
{
	ng_fill(0, 0, 32, 2, 0, 0);
	ng_text(1, 0, "SCORE", 2);
	ng_number(7, 0, score, 4, 2);
	ng_text(21, 0, "BEST", 2);
	ng_number(26, 0, best, 4, 2);
}

// --- bird --------------------------------------------------------------------------------

static void flap(void)
{
	bird_vy = -0x2C0;
	flap_anim = 12;
}

static void move_bird(void)
{
	bird_vy += 0x22;
	if (bird_vy > 0x480)
		bird_vy = 0x480;
	bird_y += bird_vy;
	if (bird_y < SKY_TOP << 8) {
		bird_y = SKY_TOP << 8;
		bird_vy = 0;
	}
	if (flap_anim)
		flap_anim--;
}

static int bird_hits(void)
{
	int wx = (world_x >> 8) + BIRD_X, y = bird_y >> 8;
	return solid(wx + 2, y + 3) || solid(wx + 14, y + 4) || solid(wx + 2, y + 12) ||
	       solid(wx + 14, y + 11) || solid(wx + 8, y + 13) || solid(wx + 8, y + 2);
}

// demo player: flap when falling close to the bottom of the next gap (a
// flap lifts the bird about 28 pixels)
static int ai_flap(void)
{
	int wx = (world_x >> 8) + BIRD_X;
	int lowest = (gap_top[next_pipe % N_GAPS] + GAP) * 8 - 19;
	if (wx < PIPE_FIRST * 8 - 64)
		lowest = 120;
	return (bird_y >> 8) > lowest && bird_vy > 0;
}

// --- game ----------------------------------------------------------------------------------

static void reset_world(void)
{
	world_x = 0;
	drawn_to = 0;
	ng_scroll(0, 0);
	draw_ahead();
	bird_y = 100 << 8;
	bird_vy = 0;
	next_pipe = 0;
}

static void new_game(int is_demo)
{
	demo = is_demo;
	score = 0;
	reset_world();                      // also draws over the title
	draw_score();
	if (demo)
		ng_center(1, "DEMO - PRESS START", 1);
	mode = M_READY;
	timer = 0;
}

static void title(void)
{
	reset_world();
	ng_big_center(5, "FLAPPY", 1, T_QUAD0);
	ng_big_center(10, "CHIP", 3, T_QUAD0);
	ng_center(19, "A, SPACE OR UP   FLAP", 2);
	ng_center(20, "Q   BACK TO THE MENU", 2);
	draw_score();
	mode = M_TITLE;
	timer = 0;
}

void game_main(void)
{
	ng_begin(art_chr, ART_TILES, art_palette);
	ng_split(SKY_TOP);
	title();

	while (!ng_quit()) {
		uint8_t p = ng_pressed();
		timer++;
		if (demo && mode != M_TITLE && (p & (BTN_START | BTN_A))) {
			demo = 0;
			title();
			ng_frame();
			continue;
		}

		switch (mode) {
		case M_TITLE:
			ng_center(16, (timer >> 5) & 1 ? "           " : "PRESS START", 1);
			bird_y = (100 << 8) + ((timer & 32 ? 31 - (timer & 31) : timer & 31) << 7);
			if (p & (BTN_START | BTN_A | BTN_UP)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_READY:                       // hover until the first flap
			bird_y = (100 << 8) + ((timer & 32 ? 31 - (timer & 31) : timer & 31) << 7);
			ng_center(12, (timer >> 4) & 1 ? "" : "GET READY", 1);
			if ((p & (BTN_A | BTN_UP)) || (demo && timer > 60)) {
				ng_fill(0, 12, 32, 1, 0, 0);
				flap();
				mode = M_PLAY;
			}
			break;

		case M_PLAY:
			if (demo ? ai_flap() : (p & (BTN_A | BTN_UP | BTN_B)) != 0)
				flap();
			move_bird();
			world_x += 0x100 + (score < 40 ? score * 4 : 160);
			draw_ahead();
			// passed a pipe?
			if ((world_x >> 8) + BIRD_X > (PIPE_FIRST + next_pipe * PIPE_EVERY + 2) * 8) {
				next_pipe++;
				score++;
				draw_score();
			}
			if (bird_hits()) {
				mode = M_FALL;
				timer = 0;
				bird_vy = 0;
				if (!demo && score > best)
					best = score;
			}
			break;

		case M_FALL:
			if (timer > 20 && (bird_y >> 8) < GROUND_ROW * 8 - 14)
				move_bird();
			if (timer == 60) {
				draw_score();
				ng_text(((world_x >> 11) + 11) & 63, 12, "GAME OVER", 3);
				mode = M_OVER;
				timer = 0;
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 90 : 1200))
				title();
			break;
		}

		ng_scroll((world_x >> 8) & 511, 0);
		int frame = mode == M_FALL || mode == M_OVER ? S_BIRD_DOWN - S_BIRD_UP :
		            flap_anim > 8 ? 0 : flap_anim > 4 ? 2 : flap_anim ? 4 : ((timer >> 3) % 3) * 2;
		ng_sprite(BIRD_X, bird_y >> 8, S_BIRD_UP + frame, 0, NG_BIG | (mode >= M_FALL ? NG_VFLIP : 0));
		ng_frame();
	}
}

#ifdef GAME_HOST
#include <stdio.h>
void game_report(void)
{
	printf("mode=%d score=%u best=%u x=%d y=%d demo=%d\n", mode, (unsigned)score, (unsigned)best,
	       (int)(world_x >> 8), (int)(bird_y >> 8), demo);
}
#endif
