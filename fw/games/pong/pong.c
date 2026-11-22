// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Pong against the computer: first to 7 wins. Where the ball meets the
// paddle sets its angle, and every hit makes it faster. The computer's
// paddle has a top speed and misjudges a little, so it can be beaten.
//
// Paddles and ball are sprites; positions are in 1/256 pixel.

#include "ngame.h"
#include "art.h"

#define TOP         24              // field, pixels
#define BOTTOM      224
#define PAD_H       32
#define LEFT_X      12
#define RIGHT_X     236
#define WIN_SCORE   7
#define BALL_R      3

enum { M_TITLE, M_SERVE, M_PLAY, M_POINT, M_OVER };

static int32_t  bx, by, vx, vy;
static int32_t  pad_y[2];               // top edge, 1/256 pixel
static int      points[2], aim_error[2];
static int      serve_dir, hits;
static int      wins, losses;
static int      mode, timer, demo;

// --- drawing ------------------------------------------------------------------------

static void draw_scores(void)
{
	char s[2] = {0, 0};
	s[0] = '0' + points[0];
	ng_big_text(9, 4, s, 3, T_QUAD0);
	s[0] = '0' + points[1];
	ng_big_text(20, 4, s, 3, T_QUAD0);
}

static void draw_table(void)
{
	ng_clear();
	ng_fill(0, 2, 32, 1, T_WALL, 0);
	ng_fill(0, 28, 32, 1, T_WALL_B, 0);
	for (int r = 3; r < 28; r++) {
		ng_tile(15, r, T_NET, 0);
		ng_tile(16, r, T_NET | NG_TILE_HFLIP, 0);
	}
	ng_text(1, 0, "YOU", 2);
	ng_text(28, 0, "CPU", 1);
	ng_text(7, 0, "WINS", 0);
	ng_number(12, 0, wins, 2, 0);
	ng_text(16, 0, "LOSSES", 0);
	ng_number(23, 0, losses, 2, 0);
}

static void draw_paddle(int side)
{
	int x = side ? RIGHT_X : LEFT_X, y = pad_y[side] >> 8;
	int top = side ? T_PAD_TOP2 : T_PAD_TOP, mid = side ? T_PAD_MID2 : T_PAD_MID;
	ng_sprite(x, y, top, 0, 0);
	ng_sprite(x, y + 8, mid, 0, 0);
	ng_sprite(x, y + 16, mid, 0, NG_VFLIP);
	ng_sprite(x, y + 24, top, 0, NG_VFLIP);
}

// --- paddles ---------------------------------------------------------------------------

static void clamp_paddle(int side)
{
	if (pad_y[side] < TOP << 8)
		pad_y[side] = TOP << 8;
	if (pad_y[side] > (BOTTOM - PAD_H) << 8)
		pad_y[side] = (BOTTOM - PAD_H) << 8;
}

// computer player: follow the ball when it comes this way
static void ai_paddle(int side, int32_t max_speed)
{
	int coming = side ? vx > 0 : vx < 0;
	int32_t target = coming && mode == M_PLAY ? by + (aim_error[side] << 8) : (TOP + BOTTOM) << 7;
	int32_t centre = pad_y[side] + (PAD_H << 7);
	int32_t d = target - centre;
	if (d > max_speed) d = max_speed;
	if (d < -max_speed) d = -max_speed;
	pad_y[side] += d;
	clamp_paddle(side);
}

static void player_paddle(void)
{
	uint8_t b = ng_buttons();
	int32_t speed = b & BTN_B ? 0x500 : 0x340;
	if (b & BTN_UP)
		pad_y[0] -= speed;
	if (b & BTN_DOWN)
		pad_y[0] += speed;
	clamp_paddle(0);
}

// --- ball --------------------------------------------------------------------------------

static void serve(void)
{
	bx = 128 << 8;
	by = ((TOP + BOTTOM) / 2) << 8;
	vx = 0;
	vy = 0;
	hits = 0;
	aim_error[0] = ng_rand_range(25) - 12;
	aim_error[1] = ng_rand_range(25) - 12;
	mode = M_SERVE;
	timer = 0;
}

static void hit_paddle(int side)
{
	int32_t off = by - (pad_y[side] + (PAD_H << 7));       // -19 .. 19 pixels, 1/256
	int32_t speed = (vx < 0 ? -vx : vx) + 0x18;
	if (speed > 0x500)
		speed = 0x500;
	vx = side ? -speed : speed;
	vy = off * 3 / 32;                                      // up to about 1.8 px per frame
	hits++;
	aim_error[!side] = ng_rand_range(25 + hits) - 12 - hits / 2;
}

static void move_ball(void)
{
	bx += vx;
	by += vy;
	if ((by >> 8) - BALL_R < TOP) {
		by = (TOP + BALL_R) << 8;
		vy = -vy;
	}
	if ((by >> 8) + BALL_R > BOTTOM) {
		by = (BOTTOM - BALL_R) << 8;
		vy = -vy;
	}
	int x = bx >> 8, y = by >> 8;
	if (vx < 0 && x - BALL_R <= LEFT_X + 8 && x - BALL_R > LEFT_X - 4 &&
	    y >= (pad_y[0] >> 8) - BALL_R && y <= (pad_y[0] >> 8) + PAD_H + BALL_R)
		hit_paddle(0);
	if (vx > 0 && x + BALL_R >= RIGHT_X && x + BALL_R < RIGHT_X + 12 &&
	    y >= (pad_y[1] >> 8) - BALL_R && y <= (pad_y[1] >> 8) + PAD_H + BALL_R)
		hit_paddle(1);

	if (x < -8 || x > 264) {
		int winner = x < 0;
		points[winner]++;
		serve_dir = winner ? -1 : 1;        // towards the one who lost the point
		draw_scores();
		mode = M_POINT;
		timer = 0;
	}
}

// --- game ---------------------------------------------------------------------------------

static void new_game(int is_demo)
{
	demo = is_demo;
	points[0] = points[1] = 0;
	pad_y[0] = pad_y[1] = ((TOP + BOTTOM - PAD_H) / 2) << 8;
	draw_table();
	draw_scores();
	if (demo)
		ng_center(1, "DEMO - PRESS START", 1);
	serve_dir = ng_rand_range(2) ? 1 : -1;
	serve();
}

static void title(void)
{
	draw_table();
	ng_fill(2, 5, 28, 21, 0, 0);
	ng_big_center(6, "PONG", 2, T_QUAD0);
	ng_center(13, "FIRST TO 7 POINTS WINS", 0);
	ng_center(20, "UP/DOWN OR W/S   MOVE", 3);
	ng_center(21, "J   MOVE FASTER", 3);
	ng_center(22, "Q   BACK TO THE MENU", 3);
	pad_y[0] = pad_y[1] = ((TOP + BOTTOM - PAD_H) / 2) << 8;
	mode = M_TITLE;
	timer = 0;
}

void game_main(void)
{
	ng_begin(art_chr, ART_TILES, art_palette);
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
			if (p & (BTN_START | BTN_A)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_SERVE:
			if (demo) ai_paddle(0, 0x2C0); else player_paddle();
			ai_paddle(1, 0x2C0);
			if (timer == 50) {
				vx = serve_dir * 0x200;
				vy = (ng_rand_range(2) ? 1 : -1) * (0x80 + ng_rand_range(0x80));
				mode = M_PLAY;
			}
			break;

		case M_PLAY:
			if (demo) ai_paddle(0, 0x2C0); else player_paddle();
			ai_paddle(1, 0x200 + hits * 8 > 0x300 ? 0x300 : 0x200 + hits * 8);
			move_ball();
			break;

		case M_POINT:
			if (timer == 40) {
				if (points[0] == WIN_SCORE || points[1] == WIN_SCORE) {
					if (!demo) {
						if (points[0] == WIN_SCORE) wins++; else losses++;
					}
					ng_fill(5, 15, 22, 3, 0, 0);
					ng_center(16, points[0] == WIN_SCORE ? "YOU WIN!" : "CPU WINS", 1);
					mode = M_OVER;
					timer = 0;
				} else {
					serve();
				}
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 90 : 600))
				title();
			break;
		}

		if (mode != M_TITLE) {
			draw_paddle(0);
			draw_paddle(1);
		}
		if (mode == M_PLAY || mode == M_SERVE)
			ng_sprite((bx >> 8) - BALL_R, (by >> 8) - BALL_R, T_BALL, 0, 0);
		ng_frame();
	}
}

#ifdef GAME_HOST
#include <stdio.h>
void game_report(void)
{
	printf("mode=%d you=%d cpu=%d hits=%d wins=%d losses=%d demo=%d\n", mode, points[0], points[1],
	       hits, wins, losses, demo);
}
#endif
