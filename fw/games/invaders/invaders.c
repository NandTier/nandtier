// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Alien Raid: shoot the descending alien formation before it lands. The
// fewer aliens are left, the faster they march. Shields soak up shots from
// both sides; a saucer crosses the top now and then for bonus points.
//
// Aliens, ship, shots and the saucer are sprites; stars, shields and the
// ground are background tiles. The shields are worn away tile by tile.

#include "ngame.h"
#include "art.h"

#define AROWS       5
#define ACOLS       8
#define ASTEP_X     24
#define ASTEP_Y     18
#define SHIP_Y      200
#define SHIELD_ROW  22              // tile rows 22-23
#define GROUND_ROW  28
#define MAX_BOMBS   4
#define MAX_BOOMS   4

enum { M_TITLE, M_PLAY, M_HIT, M_WAVE, M_OVER };

static uint8_t  alive[AROWS];           // bit c: column c
static int      n_alive;
static int      fx, fy, fdir, fanim;    // formation position, direction
static int      march_timer;

static int      ship_x, lives, wave;
static int      shot_x, shot_y;         // shot_y < 0: no shot
static struct { int x, y, anim; } bombs[MAX_BOMBS];     // y < 0: unused
static struct { int x, y, timer; } booms[MAX_BOOMS];
static int      ufo_x, ufo_dir, ufo_timer;

static uint8_t  shield[2][32];          // 3 whole .. 0 gone
static uint32_t score, best;
static int      mode, timer, demo, demo_target;

static const uint8_t ALIEN_TILE[AROWS] = {S_SQUID1, S_CRAB1, S_CRAB1, S_OCTO1, S_OCTO1};
static const uint8_t ALIEN_PTS[AROWS]  = {30, 20, 20, 10, 10};

// --- drawing ------------------------------------------------------------------------

static void draw_hud(void)
{
	ng_text(1, 0, "SCORE", 3);
	ng_number(7, 0, score, 6, 0);
	ng_text(15, 0, "WAVE", 3);
	ng_number(20, 0, wave + 1, 2, 0);
	for (int i = 0; i < 5; i++)
		ng_tile(25 + i, 0, i < lives - 1 ? T_LIFE : 0, 0);
}

static void draw_shield_tile(int r, int c)
{
	static const uint8_t t[4] = {0, T_SHIELD1, T_SHIELD2, T_SHIELD3};
	ng_tile(c, SHIELD_ROW + r, t[shield[r][c]], 0);
}

static void draw_background(void)
{
	ng_clear();
	for (int r = 2; r < GROUND_ROW; r++)
		for (int c = 0; c < 32; c++) {
			int h = (c * 7 + r * 13 + c * r) % 23;
			if (h == 0) ng_tile(c, r, T_STAR1, 0);
			if (h == 5) ng_tile(c, r, T_STAR2, 0);
		}
	ng_fill(0, GROUND_ROW, 32, 1, T_GROUND, 0);
}

static void build_shields(void)
{
	for (int r = 0; r < 2; r++)
		for (int c = 0; c < 32; c++) {
			int x = c % 8;
			shield[r][c] = x >= 2 && x <= 5 && !(r == 1 && (x == 3 || x == 4)) ? 3 : 0;
			draw_shield_tile(r, c);
		}
}

// --- formation ----------------------------------------------------------------------

static void new_wave(void)
{
	for (int r = 0; r < AROWS; r++)
		alive[r] = 0xFF;
	n_alive = AROWS * ACOLS;
	fx = 24;
	fy = 40 + (wave < 5 ? wave : 5) * 8;
	fdir = 1;
	march_timer = 0;
	shot_y = -1;
	for (int i = 0; i < MAX_BOMBS; i++)
		bombs[i].y = -1;
	ufo_timer = 600;
	ufo_dir = 0;
}

static int lowest_row(int c)        // lowest living alien in column c, or -1
{
	for (int r = AROWS - 1; r >= 0; r--)
		if (alive[r] >> c & 1)
			return r;
	return -1;
}

static void march(void)
{
	int interval = 1 + n_alive / 3;
	if (++march_timer < interval)
		return;
	march_timer = 0;
	fanim ^= 1;

	int lo = ACOLS, hi = -1, bottom = 0;
	for (int r = 0; r < AROWS; r++)
		for (int c = 0; c < ACOLS; c++)
			if (alive[r] >> c & 1) {
				if (c < lo) lo = c;
				if (c > hi) hi = c;
				bottom = r;
			}
	int nx = fx + fdir * 3;
	if (nx + lo * ASTEP_X < 8 || nx + hi * ASTEP_X + 16 > 248) {
		fdir = -fdir;
		fy += 8;
	} else {
		fx = nx;
	}
	// aliens eat into the shields they pass through
	int ay = fy + bottom * ASTEP_Y + 9;
	if (ay >= SHIELD_ROW * 8) {
		int r = (ay >> 3) - SHIELD_ROW;
		if (r >= 0 && r < 2)
			for (int c = 0; c < ACOLS; c++)
				if (alive[bottom] >> c & 1)
					for (int t = (fx + c * ASTEP_X + 2) >> 3; t <= (fx + c * ASTEP_X + 13) >> 3; t++)
						if (t >= 0 && t < 32 && shield[r][t]) {
							shield[r][t] = 0;
							draw_shield_tile(r, t);
						}
	}
	if (ay >= SHIP_Y + 4)
		lives = 1, mode = M_HIT, timer = 0;     // landed: the game is over
}

static void boom(int x, int y)
{
	for (int i = 0; i < MAX_BOOMS; i++)
		if (booms[i].timer == 0) {
			booms[i].x = x;
			booms[i].y = y;
			booms[i].timer = 14;
			return;
		}
}

// --- shots -----------------------------------------------------------------------------

static int hit_shield(int x, int y)
{
	int r = (y >> 3) - SHIELD_ROW, c = x >> 3;
	if (r < 0 || r > 1 || c < 0 || c > 31 || shield[r][c] == 0)
		return 0;
	shield[r][c]--;
	draw_shield_tile(r, c);
	return 1;
}

static void add_score(int n)
{
	score += n;
	draw_hud();
}

static void move_shot(void)
{
	if (shot_y < 0)
		return;
	shot_y -= 5;
	int x = shot_x + 3;
	if (shot_y < 16) {
		shot_y = -1;
		return;
	}
	if (hit_shield(x, shot_y)) {
		shot_y = -1;
		return;
	}
	if (ufo_dir && shot_y < 40 && x >= ufo_x + 1 && x <= ufo_x + 14) {
		boom(ufo_x, 24);
		add_score(50 + 50 * ng_rand_range(6));
		ufo_dir = 0;
		ufo_timer = 900;
		shot_y = -1;
		return;
	}
	for (int r = 0; r < AROWS; r++) {
		int ay = fy + r * ASTEP_Y;
		if (shot_y < ay + 1 || shot_y > ay + 9)
			continue;
		for (int c = 0; c < ACOLS; c++) {
			int ax = fx + c * ASTEP_X;
			if ((alive[r] >> c & 1) && x >= ax + 2 && x <= ax + 13) {
				alive[r] &= ~(1 << c);
				n_alive--;
				boom(ax, ay - 3);
				add_score(ALIEN_PTS[r]);
				shot_y = -1;
				return;
			}
		}
	}
}

static void drop_bombs(void)
{
	int chance = 60 - wave * 6;
	if (chance < 18) chance = 18;
	if (ng_rand_range(chance) == 0) {
		int c = ng_rand_range(ACOLS), r = lowest_row(c);
		if (r >= 0)
			for (int i = 0; i < MAX_BOMBS; i++)
				if (bombs[i].y < 0) {
					bombs[i].x = fx + c * ASTEP_X + 4;
					bombs[i].y = fy + r * ASTEP_Y + 9;
					break;
				}
	}
	int speed = 2 + (wave >= 2) + (wave >= 5);
	for (int i = 0; i < MAX_BOMBS; i++) {
		if (bombs[i].y < 0)
			continue;
		bombs[i].y += speed;
		bombs[i].anim++;
		int x = bombs[i].x + 3, y = bombs[i].y + 6;
		if (y >= GROUND_ROW * 8) {
			bombs[i].y = -1;
		} else if (hit_shield(x, y)) {
			bombs[i].y = -1;
		} else if (mode == M_PLAY && y >= SHIP_Y + 2 && y <= SHIP_Y + 13 &&
		           x >= ship_x + 2 && x <= ship_x + 13) {
			bombs[i].y = -1;
			boom(ship_x, SHIP_Y);
			mode = M_HIT;
			timer = 0;
		}
	}
}

static void move_ufo(void)
{
	if (ufo_dir == 0) {
		if (--ufo_timer <= 0) {
			ufo_dir = ng_rand_range(2) ? 1 : -1;
			ufo_x = ufo_dir > 0 ? -16 : 256;
		}
		return;
	}
	ufo_x += ufo_dir;
	if (ufo_x < -16 || ufo_x > 256) {
		ufo_dir = 0;
		ufo_timer = 900;
	}
}

// --- ship -------------------------------------------------------------------------------

static void move_ship(void)
{
	uint8_t b = ng_buttons(), p = ng_pressed();
	if (demo) {
		// line up under a living column, fire whenever possible
		if (timer % 90 == 0 || lowest_row(demo_target) < 0) {
			for (int k = 0; k < ACOLS; k++) {
				demo_target = ng_rand_range(ACOLS);
				if (lowest_row(demo_target) >= 0)
					break;
			}
		}
		int tx = fx + demo_target * ASTEP_X;
		b = tx < ship_x - 1 ? BTN_LEFT : tx > ship_x + 1 ? BTN_RIGHT : 0;
		p = (tx - ship_x < 12 && ship_x - tx < 12) ? BTN_A : 0;
	}
	if (b & BTN_LEFT)
		ship_x -= 2;
	if (b & BTN_RIGHT)
		ship_x += 2;
	if (ship_x < 8) ship_x = 8;
	if (ship_x > 232) ship_x = 232;
	if ((p & (BTN_A | BTN_UP)) && shot_y < 0) {
		shot_x = ship_x + 4;
		shot_y = SHIP_Y - 4;
	}
}

// --- game -------------------------------------------------------------------------------

static void new_game(int is_demo)
{
	demo = is_demo;
	score = 0;
	lives = 3;
	wave = 0;
	ship_x = 120;
	draw_background();
	build_shields();
	new_wave();
	draw_hud();
	if (demo)
		ng_center(1, "DEMO - PRESS START", 1);
	mode = M_PLAY;
	timer = 0;
}

static void title(void)
{
	draw_background();
	build_shields();
	ng_big_center(4, "ALIEN", 2, T_QUAD0);
	ng_big_center(9, "RAID", 2, T_QUAD0);
	ng_text(10, 15, "= 30 POINTS", 0);
	ng_text(10, 17, "= 20 POINTS", 0);
	ng_text(10, 19, "= 10 POINTS", 0);
	ng_text(10, 21, "= ??? BONUS", 0);
	ng_center(26, "MOVE: LEFT/RIGHT  FIRE: A", 3);
	ng_center(27, "Q: BACK TO THE MENU", 3);
	ng_text(1, 0, "BEST", 3);
	ng_number(6, 0, best, 6, 0);
	for (int i = 0; i < 5; i++)
		ng_tile(25 + i, 0, 0, 0);
	for (int i = 0; i < MAX_BOOMS; i++)
		booms[i].timer = 0;
	n_alive = 0;
	mode = M_TITLE;
	timer = 0;
}

static void draw_sprites(void)
{
	if (mode == M_TITLE) {
		ng_sprite(60, 118, S_SQUID1 + fanim * 2, 0, NG_BIG);
		ng_sprite(60, 134, S_CRAB1 + fanim * 2, 0, NG_BIG);
		ng_sprite(60, 150, S_OCTO1 + fanim * 2, 0, NG_BIG);
		ng_sprite(60, 163, S_UFO, 0, NG_BIG);
		if ((timer & 31) == 0)
			fanim ^= 1;
		return;
	}
	if (mode == M_PLAY || mode == M_WAVE)
		ng_sprite(ship_x, SHIP_Y, S_SHIP, 0, NG_BIG);
	if (shot_y >= 0)
		ng_sprite(shot_x, shot_y, T_BULLET, 0, 0);
	for (int i = 0; i < MAX_BOMBS; i++)
		if (bombs[i].y >= 0)
			ng_sprite(bombs[i].x, bombs[i].y, (bombs[i].anim >> 2) & 1 ? T_BOMB2 : T_BOMB1, 0, 0);
	for (int i = 0; i < MAX_BOOMS; i++)
		if (booms[i].timer) {
			booms[i].timer--;
			ng_sprite(booms[i].x, booms[i].y, S_BOOM, 0, NG_BIG | ((booms[i].timer >> 2) & 1 ? NG_HFLIP : 0));
		}
	if (ufo_dir)
		ng_sprite(ufo_x, 24, S_UFO, 0, NG_BIG);
	for (int r = 0; r < AROWS; r++)
		for (int c = 0; c < ACOLS; c++)
			if (alive[r] >> c & 1)
				ng_sprite(fx + c * ASTEP_X, fy + r * ASTEP_Y, ALIEN_TILE[r] + fanim * 2, 0, NG_BIG);
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
			ng_center(24, (timer >> 5) & 1 ? "           " : "PRESS START", 1);
			if (p & (BTN_START | BTN_A)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_PLAY:
			move_ship();
			move_shot();
			march();
			drop_bombs();
			move_ufo();
			if (mode == M_PLAY && n_alive == 0) {
				mode = M_WAVE;
				timer = 0;
				ng_center(18, "WAVE CLEARED!", 1);
			}
			break;

		case M_HIT:
			drop_bombs();
			if (timer == 1) {
				lives--;
				draw_hud();
			}
			if (timer == 90) {
				if (lives > 0) {
					mode = M_PLAY;
					ship_x = 120;
					for (int i = 0; i < MAX_BOMBS; i++)
						bombs[i].y = -1;
				} else {
					if (!demo && score > best)
						best = score;
					ng_fill(8, 13, 16, 5, 0, 0);
					ng_center(14, "GAME OVER", 1);
					ng_center(16, "PRESS START", 0);
					mode = M_OVER;
					timer = 0;
				}
			}
			break;

		case M_WAVE:
			move_ship();
			if (timer == 120) {
				ng_fill(0, 18, 32, 1, 0, 0);
				wave++;
				draw_hud();
				build_shields();
				new_wave();
				mode = M_PLAY;
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 90 : 1200))
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
	printf("mode=%d score=%u best=%u wave=%d lives=%d aliens=%d demo=%d\n", mode, (unsigned)score,
	       (unsigned)best, wave, lives, n_alive, demo);
}
#endif
