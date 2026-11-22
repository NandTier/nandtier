// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Brick Breaker: bounce the ball off the paddle and clear every brick.
// Where the ball hits the paddle sets its angle; it gets faster with every
// hit. Steel bricks take two hits. Five levels, then they repeat faster.
//
// Bricks are background tiles (two per brick), the paddle and the ball are
// sprites. Positions are in 1/256 pixel.

#include "ngame.h"
#include "art.h"

#define ROWS        8
#define COLS        15
#define BRICK_ROW0  5               // tile row of the top brick row
#define PADDLE_Y    216
#define FIELD_L     8
#define FIELD_R     248
#define FIELD_T     24
#define BALL_R      2

enum { M_TITLE, M_SERVE, M_PLAY, M_LOST, M_CLEAR, M_OVER };

static const char *const LEVELS[][ROWS] = {
	{"...............", "111111111111111", "222222222222222", "333333333333333",
	 "444444444444444", "111111111111111", "222222222222222", "..............."},
	{"S.............S", "1S...........S1", "21S.........S12", "321S.......S123",
	 "4321S.....S1234", "14321S...S12341", "214321SSS123412", "..............."},
	{"...............", ".1111.....2222.", ".1SS1.....2SS2.", ".1111.....2222.",
	 "...............", ".3333.....4444.", ".3SS3.....4SS4.", ".3333.....4444."},
	{"SSSSSSSSSSSSSSS", "1.1.1.1.1.1.1.1", ".2.2.2.2.2.2.2.", "3.3.3.3.3.3.3.3",
	 ".4.4.4.4.4.4.4.", "1.1.1.1.1.1.1.1", "...............", "SSSSSS...SSSSSS"},
	{"......444......", ".....43334.....", "....4322234....", "...432111234...",
	 "...432111234...", "....4322234....", ".....43334.....", "......444......"},
};
#define N_LEVELS 5

static uint8_t  bricks[ROWS][COLS];     // 0 none, 1-4 colour, 5 steel, 6 steel hit once
static int      left;                   // bricks still to clear
static int      level, lives;
static uint32_t score, best;
static int      mode, timer, demo;

static int32_t  pad_x;                  // left edge, pixels
static int      pad_w = 32;
static int32_t  bx, by, vx, vy;         // ball centre and velocity, 1/256 pixel
static int32_t  speed;

// directions for the paddle bounce, 1/256: x, -y (from steep left to steep right)
static const int16_t DIRS[9][2] = {
	{-202, 158}, {-169, 192}, {-128, 222}, {-79, 243}, {0, 256},
	{79, 243}, {128, 222}, {169, 192}, {202, 158},
};

// --- drawing ----------------------------------------------------------------------

static void draw_cell(int r, int c)
{
	int col = 1 + c * 2, row = BRICK_ROW0 + r;
	int b = bricks[r][c];
	if (b == 0) {
		ng_tile(col, row, T_BACK, 3);
		ng_tile(col + 1, row, T_BACK, 3);
	} else if (b >= 5) {
		ng_tile(col, row, T_STEEL_L, b == 6 ? 0 : 3);
		ng_tile(col + 1, row, T_STEEL_R, b == 6 ? 0 : 3);
	} else {
		ng_tile(col, row, T_BRICK_L, b - 1);
		ng_tile(col + 1, row, T_BRICK_R, b - 1);
	}
}

static void draw_hud(void)
{
	ng_text(1, 0, "SCORE", 3);
	ng_number(7, 0, score, 6, 0);
	ng_text(15, 0, "LEVEL", 3);
	ng_number(21, 0, level + 1, 2, 0);
	for (int i = 0; i < 6; i++)
		ng_tile(25 + i, 0, i < lives - 1 ? T_LIFE : 0, 0);
}

static void draw_field(void)
{
	ng_clear();
	ng_fill(0, 2, 32, 1, T_WALL_H, 0);
	ng_fill(0, 3, 1, 27, T_WALL_V, 0);
	ng_fill(31, 3, 1, 27, T_WALL_V, 0);
	ng_fill(1, 3, 30, 27, T_BACK, 3);
}

static void load_level(void)
{
	left = 0;
	for (int r = 0; r < ROWS; r++) {
		for (int c = 0; c < COLS; c++) {
			char ch = LEVELS[level % N_LEVELS][r][c];
			bricks[r][c] = ch == 'S' ? 5 : ch >= '1' && ch <= '4' ? ch - '0' : 0;
			left += bricks[r][c] != 0;
			draw_cell(r, c);
		}
	}
}

static void message(const char *s)
{
	ng_fill(1, 18, 30, 1, T_BACK, 3);
	if (s)
		ng_center(18, s, 1);
}

// --- ball -------------------------------------------------------------------------

static void serve(void)
{
	mode = M_SERVE;
	timer = 0;
	speed = 0x1C0 + (level / N_LEVELS) * 0x40;
	message("PRESS A TO LAUNCH");
}

static void launch(void)
{
	int d = demo ? 3 + ng_rand_range(3) : 5;
	vx = DIRS[d][0] * speed >> 8;
	vy = -(DIRS[d][1] * speed >> 8);
	mode = M_PLAY;
	message(0);
}

static void add_score(uint32_t n)
{
	score += n;
	draw_hud();
}

// is there a wall or brick at pixel (x, y)? hits the brick if so
static int solid(int32_t x, int32_t y)
{
	if (x < FIELD_L || x >= FIELD_R || y < FIELD_T)
		return 1;
	int r = (y >> 3) - BRICK_ROW0, c = ((x >> 3) - 1) >> 1;
	if (r < 0 || r >= ROWS || bricks[r][c] == 0)
		return 0;
	if (bricks[r][c] == 5) {
		bricks[r][c] = 6;
		add_score(5);
	} else {
		bricks[r][c] = 0;
		left--;
		add_score(10 + (ROWS - 1 - r) * 5);
	}
	draw_cell(r, c);
	if (speed < 0x340)      // every hit speeds the ball up a little
		speed += 3;
	return 1;
}

static void bounce_off_paddle(void)
{
	int32_t off = (bx >> 8) - (pad_x + pad_w / 2);     // -18 .. 18
	int d = (off + pad_w / 2 + 2) * 9 / (pad_w + 4);
	if (d < 0) d = 0;
	if (d > 8) d = 8;
	vx = DIRS[d][0] * speed >> 8;
	vy = -(DIRS[d][1] * speed >> 8);
	by = (PADDLE_Y - BALL_R - 1) << 8;
}

static void move_ball(void)
{
	for (int half = 0; half < 2; half++) {
		int32_t nx = bx + vx / 2, ny = by + vy / 2;
		int32_t edge_x = (nx >> 8) + (vx > 0 ? BALL_R : -BALL_R);
		if (solid(edge_x, by >> 8))
			vx = -vx;
		else
			bx = nx;
		int32_t edge_y = (ny >> 8) + (vy > 0 ? BALL_R : -BALL_R);
		if (solid(bx >> 8, edge_y))
			vy = -vy;
		else
			by = ny;

		if (vy > 0 && (by >> 8) + BALL_R >= PADDLE_Y && (by >> 8) + BALL_R < PADDLE_Y + 6 &&
		    (bx >> 8) >= pad_x - 3 && (bx >> 8) <= pad_x + pad_w + 3)
			bounce_off_paddle();
	}
	// never too flat: the ball would take ages
	if (vy > -0x50 && vy < 0x50)
		vy = vy < 0 ? -0x50 : 0x50;
}

// --- game -------------------------------------------------------------------------

static void move_paddle(void)
{
	uint8_t b = ng_buttons();
	int step = b & BTN_B ? 5 : 3;
	if (demo) {
		int target = (mode == M_PLAY ? (bx >> 8) : 128) - pad_w / 2 + ((timer >> 6) & 7) - 4;
		b = target < pad_x - 1 ? BTN_LEFT : target > pad_x + 1 ? BTN_RIGHT : 0;
		step = 4;
	}
	if (b & BTN_LEFT)
		pad_x -= step;
	if (b & BTN_RIGHT)
		pad_x += step;
	if (pad_x < FIELD_L)
		pad_x = FIELD_L;
	if (pad_x > FIELD_R - pad_w)
		pad_x = FIELD_R - pad_w;
}

static void new_game(int is_demo)
{
	demo = is_demo;
	score = 0;
	level = 0;
	lives = 3;
	pad_x = 128 - pad_w / 2;
	draw_field();
	load_level();
	draw_hud();
	if (demo)
		ng_center(1, "DEMO - PRESS START", 1);
	serve();
}

static void title(void)
{
	draw_field();
	level = 0;
	load_level();
	ng_fill(1, 13, 30, 15, T_BACK, 3);
	ng_big_center(14, "BRICKS", 1, T_QUAD0);
	ng_center(19, "B R E A K E R", 2);
	ng_center(24, "LEFT/RIGHT MOVE  J FAST", 0);
	ng_center(25, "A OR SPACE    LAUNCH", 0);
	ng_center(26, "Q    BACK TO THE MENU", 0);
	ng_text(1, 0, "BEST", 3);
	ng_number(6, 0, best, 6, 0);
	mode = M_TITLE;
	timer = 0;
}

static void draw_sprites(void)
{
	if (mode == M_SERVE || mode == M_PLAY)
		ng_sprite((bx >> 8) - 3, (by >> 8) - 3, T_BALL, 0, 0);
	if (mode != M_TITLE && mode != M_OVER) {
		ng_sprite(pad_x, PADDLE_Y, T_PAD_L, 0, 0);
		for (int x = 8; x < pad_w - 8; x += 8)
			ng_sprite(pad_x + x, PADDLE_Y, T_PAD_M, 0, 0);
		ng_sprite(pad_x + pad_w - 8, PADDLE_Y, T_PAD_L, 0, NG_HFLIP);
	}
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
			ng_center(21, (timer >> 5) & 1 ? "           " : "PRESS START", 1);
			if (p & (BTN_START | BTN_A)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_SERVE:
			move_paddle();
			bx = (pad_x + pad_w / 2) << 8;
			by = (PADDLE_Y - BALL_R - 1) << 8;
			if ((p & (BTN_A | BTN_UP | BTN_START)) || (demo && timer > 40))
				launch();
			break;

		case M_PLAY:
			move_paddle();
			move_ball();
			if (left == 0) {
				mode = M_CLEAR;
				timer = 0;
				message("LEVEL CLEAR!");
			} else if ((by >> 8) > 240) {
				mode = M_LOST;
				timer = 0;
			}
			break;

		case M_LOST:
			if (timer == 1) {
				lives--;
				draw_hud();
				message(lives ? "MISSED!" : "GAME OVER");
			}
			if (timer == 90) {
				if (lives) {
					serve();
				} else {
					if (!demo && score > best)
						best = score;
					mode = M_OVER;
					timer = 0;
				}
			}
			break;

		case M_CLEAR:
			if (timer == 120) {
				level++;
				load_level();
				draw_hud();
				serve();
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 60 : 1200))
				title();
			break;
		}
		draw_sprites();
		ng_frame();
	}
}

#ifdef GAME_HOST
#include <stdio.h>
void game_report(void)
{
	printf("mode=%d score=%u best=%u level=%d lives=%d left=%d demo=%d\n", mode, (unsigned)score,
	       (unsigned)best, level, lives, left, demo);
}
#endif
