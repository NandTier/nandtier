// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Road Rush: race up the highway, weave through the traffic. The faster
// you go, the faster the score climbs; every car you overtake is a bonus.
// Three crashes and the race is over. The grass slows you down.
//
//   left/right  steer       up or A  accelerate      down or B  brake
//
// The road scrolls vertically: it is drawn in the right half of the tile
// map (columns 32-63, shown with SCROLL_X = 256), one row just before it
// comes into view. The score line lives in the left half, rows 0-1, above
// the PPU split, where nothing scrolls.

#include "ngame.h"
#include "art.h"

#define ROAD_L      56              // asphalt, screen pixels
#define ROAD_R      200
#define LANE_W      48
#define CAR_Y       196
#define MAX_SPEED   0x600           // 1/256 pixel per frame
#define GRASS_SPEED 0x180
#define MAX_CARS    6

enum { M_TITLE, M_RACE, M_CRASH, M_OVER };

static int32_t  dist;                   // distance driven, 1/256 pixel
static int      drawn_row;              // next world row to draw
static int32_t  car_x, speed;           // player: left edge 1/256 pixel
static struct traffic {
	int32_t y, speed;               // y: top on the screen, 1/256 pixel
	int16_t x, pal, active, passed;
} cars[MAX_CARS];
static int      spawn_timer;
static int      lives, overtaken;
static uint32_t score, best;
static int      mode, timer, demo;

// --- road --------------------------------------------------------------------------------

static void draw_row(int k)             // world row k (k grows up the road)
{
	int row = -k & 31;
	int dash = (k >> 1) & 1;
	int h = (k * 37) ^ (k >> 2) * 11;
	for (int c = 0; c < 32; c++) {
		int tile = T_ASPHALT, pal = 0;
		if (c < 6 || c > 25) {
			int g = (h + c * 13) % 23;
			tile = g == 0 ? T_TREE : g == 7 ? T_BUSH : T_GRASS;
		} else if (c == 6 || c == 25) {
			tile = (k >> 1) & 1 ? T_KERB_R : T_KERB_W;
		} else if ((c == 13 || c == 19) && dash) {
			tile = T_LANE;
		}
		if ((k % 500) == 0 && k > 0 && c >= 7 && c <= 24)
			tile = T_FLAG_R;            // a finish line every 4000 pixels, for fun
		ng_tile(32 + c, row, tile, pal);
	}
}

static void draw_ahead(void)
{
	int top = ((dist >> 8) - 16) >> 3;
	while (drawn_row <= top + 2)
		draw_row(drawn_row++);
}

static void reset_road(void)
{
	dist = 0;
	drawn_row = -31;
	draw_ahead();
	ng_scroll(256, 0);
}

static void draw_hud(void)
{
	ng_text(1, 0, "SCORE", 2);
	ng_number(7, 0, score, 6, 0);
	ng_text(15, 0, "KM/H", 2);
	ng_number(20, 0, speed * 200 / MAX_SPEED, 3, speed > MAX_SPEED * 3 / 4 ? 1 : 0);
	for (int i = 0; i < 3; i++)
		ng_text(25 + i * 2, 0, i < lives ? "*" : " ", 3);
}

// --- traffic -------------------------------------------------------------------------------

static void spawn_car(void)
{
	int lane = ng_rand_range(3);
	for (int i = 0; i < MAX_CARS; i++) {
		struct traffic *t = &cars[i];
		if (t->active)
			continue;
		// keep a gap to the cars already in that lane at the top
		for (int j = 0; j < MAX_CARS; j++)
			if (cars[j].active && cars[j].x == ROAD_L + lane * LANE_W + 16 && cars[j].y < (40 << 8))
				return;
		t->active = 1;
		t->passed = 0;
		t->x = ROAD_L + lane * LANE_W + 16;
		t->y = -24 * 256;
		t->speed = 0x140 + ng_rand_range(0x180);
		t->pal = 1 + ng_rand_range(3);
		return;
	}
}

static int overlaps(int ax, int ay, int bx, int by)
{
	return ax + 3 < bx + 13 && bx + 3 < ax + 13 && ay + 1 < by + 14 && by + 1 < ay + 14;
}

static void crash(void)
{
	mode = M_CRASH;
	timer = 0;
	speed = 0;
	lives--;
	draw_hud();
}

static void move_traffic(void)
{
	int px = car_x >> 8;
	for (int i = 0; i < MAX_CARS; i++) {
		struct traffic *t = &cars[i];
		if (!t->active)
			continue;
		t->y += speed - t->speed;
		int y = t->y >> 8;
		if (y > 250 || y < -120) {
			t->active = 0;
			continue;
		}
		if (!t->passed && y > CAR_Y + 16) {
			t->passed = 1;
			overtaken++;
			score += 50;
		}
		if (mode == M_RACE && overlaps(px, CAR_Y, t->x, y)) {
			t->y -= 20 << 8;            // knocked ahead
			crash();
		}
	}
	int every = 70 - (int)(dist >> 16);
	if (every < 22)
		every = 22;
	if (speed > 0x100 && ++spawn_timer >= every) {
		spawn_timer = 0;
		spawn_car();
	}
}

// --- player ---------------------------------------------------------------------------------

// demo driver: the lane whose nearest car ahead is furthest away
static uint8_t ai_buttons(void)
{
	int best_lane = 1, best_gap = -1;
	for (int lane = 0; lane < 3; lane++) {
		int x = ROAD_L + lane * LANE_W + 16, gap = 400;
		for (int i = 0; i < MAX_CARS; i++)
			if (cars[i].active && cars[i].x == x) {
				int g = CAR_Y - (cars[i].y >> 8);
				if (g > -12 && g < gap)
					gap = g;
			}
		gap -= (lane == 1 ? 0 : 6);
		if (gap > best_gap) {
			best_gap = gap;
			best_lane = lane;
		}
	}
	int target = ROAD_L + best_lane * LANE_W + 16, x = car_x >> 8;
	uint8_t b = best_gap < 70 ? BTN_DOWN : speed < 0x480 ? BTN_UP : 0;
	if (x < target - 1) b |= BTN_RIGHT;
	if (x > target + 1) b |= BTN_LEFT;
	return b;
}

static void drive(void)
{
	uint8_t b = demo ? ai_buttons() : ng_buttons();
	if (b & (BTN_UP | BTN_A))
		speed += 0x0C;
	else if (b & (BTN_DOWN | BTN_B))
		speed -= 0x20;
	else
		speed -= 0x04;
	if (b & BTN_LEFT)
		car_x -= 0x200;
	if (b & BTN_RIGHT)
		car_x += 0x200;
	if (car_x < 8 << 8) car_x = 8 << 8;
	if (car_x > 232 << 8) car_x = 232 << 8;

	int x = car_x >> 8;
	int max = x + 4 < ROAD_L || x + 12 > ROAD_R ? GRASS_SPEED : MAX_SPEED;
	if (speed > max)
		speed -= speed - max > 0x30 ? 0x30 : speed - max;
	if (speed < 0)
		speed = 0;
}

// --- game -------------------------------------------------------------------------------------

static void new_game(int is_demo)
{
	demo = is_demo;
	score = 0;
	overtaken = 0;
	lives = 3;
	speed = 0;
	car_x = (ROAD_L + LANE_W + 16) << 8;
	for (int i = 0; i < MAX_CARS; i++)
		cars[i].active = 0;
	ng_fill(0, 0, 32, 2, 0, 0);
	reset_road();
	draw_hud();
	if (demo)
		ng_text(7, 1, "DEMO - PRESS START", 1);
	mode = M_RACE;
	timer = 0;
}

static void title(void)
{
	for (int i = 0; i < MAX_CARS; i++)
		cars[i].active = 0;
	ng_fill(0, 0, 32, 2, 0, 0);
	reset_road();
	// the title is written on the road tiles, rows that are on screen now
	ng_big_text(32 + 7, 5, "ROAD", 1, T_QUAD0);
	ng_big_text(32 + 7, 10, "RUSH", 2, T_QUAD0);
	ng_text(32 + 7, 19, "UP/A   FASTER", 0);
	ng_text(32 + 7, 20, "DOWN/B SLOWER", 0);
	ng_text(32 + 7, 21, "Q      MENU", 0);
	ng_text(1, 0, "BEST", 2);
	ng_number(6, 0, best, 6, 0);
	car_x = (ROAD_L + LANE_W + 16) << 8;
	speed = 0;
	mode = M_TITLE;
	timer = 0;
}

void game_main(void)
{
	ng_begin(art_chr, ART_TILES, art_palette);
	ng_split(16);
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
			ng_text(32 + 10, 16, (timer >> 5) & 1 ? "           " : "PRESS START", 1);
			if (p & (BTN_START | BTN_A)) {
				ng_seed(ng_frame_count() * 2654435761u);
				new_game(0);
			} else if (timer > 600) {
				new_game(1);
			}
			break;

		case M_RACE:
			drive();
			move_traffic();
			if ((timer & 7) == 0) {
				score += speed >> 8;
				draw_hud();
			}
			break;

		case M_CRASH:
			move_traffic();
			if (timer == 90) {
				if (lives == 0) {
					if (!demo && score > best)
						best = score;
					ng_text(32 + 11, ((-((dist >> 8) - 112) >> 3) & 31), " GAME OVER ", 3);
					mode = M_OVER;
					timer = 0;
				} else {
					car_x = (ROAD_L + LANE_W + 16) << 8;
					mode = M_RACE;
				}
			}
			break;

		case M_OVER:
			if ((timer > 30 && (p & (BTN_START | BTN_A))) || timer > (demo ? 90 : 1200))
				title();
			break;
		}

		dist += speed;
		draw_ahead();
		ng_scroll(256, -(dist >> 8));

		if (mode != M_TITLE) {
			int flags = NG_BIG;
			if (mode == M_CRASH && timer < 60)
				flags |= (timer >> 2) & 1 ? NG_HFLIP : NG_VFLIP;
			if (mode != M_CRASH || timer < 60 || (timer & 4))
				ng_sprite(car_x >> 8, CAR_Y, S_CAR, 0, flags);
			if (mode == M_CRASH && timer < 40)
				ng_sprite((car_x >> 8) + (timer & 2), CAR_Y - 10 - timer / 4, S_SMOKE, 3, NG_BIG);
		} else {
			ng_sprite(car_x >> 8, CAR_Y, S_CAR, 0, NG_BIG);
		}
		for (int i = 0; i < MAX_CARS; i++)
			if (cars[i].active)
				ng_sprite(cars[i].x, cars[i].y >> 8, S_CAR, cars[i].pal, NG_BIG);
		ng_frame();
	}
}

#ifdef GAME_HOST
#include <stdio.h>
void game_report(void)
{
	printf("mode=%d score=%u best=%u lives=%d overtaken=%d distance=%d demo=%d\n", mode,
	       (unsigned)score, (unsigned)best, lives, overtaken, (int)(dist >> 8), demo);
}
#endif
