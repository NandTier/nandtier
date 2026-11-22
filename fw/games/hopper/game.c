// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier Hopper: run right, jump over pits, stomp slimes, collect coins,
// hit ? blocks and reach the flag pole. Two levels.
//
// Screen: tile map rows 0-1 are the status bar (not scrolled, PPU SPLIT =
// 16), rows 2-29 the level: 14 rows of 16 x 16 blocks. The tile map is two
// screens wide; the level is copied into it one block column at a time as
// the camera moves right (it never moves left).
//
// Positions are in 1/256 pixel, in level coordinates (y = 0 is the top of
// the level area, 16 lines below the top of the screen).

#include <stdint.h>
#include "game.h"
#include "game_hal.h"
#include "game_assets.h"

#define FX(px)          ((int32_t)(px) << 8)
#define PX(fx)          ((int32_t)(fx) >> 8)

#define HUD_LINES       16
#define LEVEL_H         (LEVEL_ROWS * 16)
#define MAX_COLS        200

// physics, in 1/256 pixel per frame
#define ACCEL_WALK      14
#define ACCEL_RUN       20
#define FRICTION        12
#define SKID            36
#define MAX_WALK        0x180
#define MAX_RUN         0x280
#define GRAVITY         0x60
#define GRAVITY_HOLD    0x22
#define JUMP_SPEED      0x400
#define JUMP_RUN_BONUS  0x60
#define MAX_FALL        0x480
#define BOUNCE          0x300
#define SLIME_SPEED     0x70

// --- state -------------------------------------------------------------------------

enum mode { M_TITLE, M_PLAY, M_DYING, M_CLEAR, M_GAME_OVER, M_WIN, M_QUIT };

static uint8_t  level_map[MAX_COLS * LEVEL_ROWS];   // [column][row], changes as blocks are hit
static const struct level *lv;
static int      level_no;

static int32_t  cam_x;          // pixels
static int      loaded_cols;    // level columns copied into the tile map

static int32_t  hx, hy, hvx, hvy;   // hero
static int      h_ground, h_facing_left, h_anim, h_jump_held;

#define MAX_SLIMES 20
static struct slime {
	int32_t x, y, vx, vy;
	uint8_t state;              // 0 unused/dead, 1 walking, 2 squashed
	uint8_t timer;
} slimes[MAX_SLIMES];
static uint8_t  spawned[64];    // per enemy entry of the level

#define MAX_POPS 4
static struct pop { int32_t x, y; int timer; } pops[MAX_POPS];   // coins out of ? blocks

static uint32_t score, best;
static int      coins, lives, time_left, time_tick;
static enum mode mode;
static int      mode_timer;
static uint32_t frame;

static uint32_t oam[64];

uint32_t game_slowest_frame;    // CPU cycles of the slowest frame (logic + PPU updates)
static int      n_sprites;

// --- input ---------------------------------------------------------------------------
//
// gamepad.py sends 0x80 | buttons whenever they change (and 30 times a
// second). Plain keys from a serial terminal hold a button for a third of
// a second, which auto-repeat keeps alive.

static uint8_t pad, pad_link;
static uint8_t key_hold[7];
static int     esc_state, quit;

static void key_press(int b)
{
	key_hold[b] = 20;
}

static void read_input(void)
{
	int k;
	while ((k = hal_key()) >= 0) {
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
		case 'j': case 'J': key_press(5); break;
		case ' ': case 'k': case 'K': key_press(6); break;
		case 'q': case 'Q': quit = 1; break;
		default: break;
		}
	}
}

static uint8_t buttons(void)
{
	uint8_t b = pad_link ? pad : 0;
	for (int i = 0; i < 7; i++) {
		if (key_hold[i]) {
			b |= 1 << i;
			key_hold[i]--;
		}
	}
	return b;
}

// --- video ----------------------------------------------------------------------------

static void wait_frame(void)
{
	uint32_t f = hal_ppu_read(PPU_STATUS) >> 16;
	while ((hal_ppu_read(PPU_STATUS) >> 16) == f)
		;
	frame++;
}

static void set_tile(int col, int row, int tile)
{
	hal_ppu_write(PPU_NAMETAB + ((row << 6) + col) * 4, tile);
}

static void text(int col, int row, const char *s)
{
	for (; *s; s++, col++)
		set_tile(col, row, *s >= 0x20 && *s < 0x60 ? *s - 0x20 : 0);
}

static void number(int col, int row, uint32_t v, int digits)
{
	char buf[8];
	for (int i = digits - 1; i >= 0; i--) {
		buf[i] = '0' + v % 10;
		v /= 10;
	}
	buf[digits] = 0;
	text(col, row, buf);
}

static void clear_map(void)
{
	for (int i = 0; i < 64 * 32; i++)
		hal_ppu_write(PPU_NAMETAB + i * 4, 0);
}

// draw level block column `col` into its place in the two-screen tile map
static void draw_column(int col)
{
	int tc = (col * 2) & 63;
	const uint8_t *cells = &level_map[col * LEVEL_ROWS];
	for (int row = 0; row < LEVEL_ROWS; row++) {
		const uint8_t *t = block_tiles[col < lv->width ? cells[row] : BLK_SKY];
		int tr = 2 + row * 2;
		set_tile(tc, tr, t[0]);
		set_tile(tc + 1, tr, t[1]);
		set_tile(tc, tr + 1, t[2]);
		set_tile(tc + 1, tr + 1, t[3]);
	}
}

static void redraw_block(int col, int row)
{
	const uint8_t *t = block_tiles[level_map[col * LEVEL_ROWS + row]];
	int tc = (col * 2) & 63, tr = 2 + row * 2;
	set_tile(tc, tr, t[0]);
	set_tile(tc + 1, tr, t[1]);
	set_tile(tc, tr + 1, t[2]);
	set_tile(tc + 1, tr + 1, t[3]);
}

static void sprite(int32_t x, int32_t y, int tile, int hflip)
{
	if (n_sprites >= 64)
		return;
	int sx = x - cam_x, sy = y + HUD_LINES;
	if (sx <= -16 || sx >= 256 || sy < 0 || sy >= 240)
		return;
	oam[n_sprites++] = OAM_ENTRY(sy, sx, tile, 0, hflip, 0, 1, 0);
}

static void upload_sprites(void)
{
	for (int i = 0; i < 64; i++)
		hal_ppu_write(PPU_OAM + i * 4, i < n_sprites ? oam[i] : OAM_HIDDEN);
	n_sprites = 0;
}

static void load_graphics(void)
{
	// a graphics pack on the SD card replaces the built-in graphics
	if (hal_load_sd_graphics() == 0)
		return;
	for (int i = 0; i < 2048; i++)
		hal_ppu_write(PPU_CHR + i * 4, game_chr[i]);
	for (int i = 0; i < 128; i++)
		hal_ppu_write(PPU_PALETTE + i * 4, game_palette[i]);
}

static void set_night(int night)
{
	for (int i = 0; i < 16; i++)
		hal_ppu_write(PPU_PALETTE + i * 4, night ? game_palette_night[i] : game_palette[i]);
}

// --- status bar --------------------------------------------------------------------

static void draw_hud_labels(void)
{
	for (int c = 0; c < 32; c++) {
		set_tile(c, 0, 0);
		set_tile(c, 1, 0);
	}
	text(1, 0, "SCORE");
	text(9, 0, "COINS");
	text(16, 0, "WORLD");
	text(23, 0, "TIME");
	text(28, 0, "LIFE");
}

static void draw_hud(void)
{
	number(1, 1, score, 6);
	number(10, 1, coins, 2);
	text(17, 1, lv ? lv->name : "1-1");
	number(23, 1, time_left > 0 ? time_left : 0, 3);
	number(29, 1, lives, 1);
}

// --- level -----------------------------------------------------------------------------

static int block_at(int32_t px, int32_t py)     // pixel position in the level
{
	if (px < 0 || py < 0)
		return BLK_SKY;
	int col = px >> 4, row = py >> 4;
	if (col >= lv->width || row >= LEVEL_ROWS)
		return BLK_SKY;
	return level_map[col * LEVEL_ROWS + row];
}

static int solid_at(int32_t px, int32_t py)
{
	if (px < 0)
		return 1;                               // left edge of the level
	return block_solid[block_at(px, py)];
}

static void set_block(int col, int row, int code)
{
	level_map[col * LEVEL_ROWS + row] = code;
	redraw_block(col, row);
}

static void start_level(void)
{
	lv = &game_levels[level_no];
	for (int i = 0; i < lv->width * LEVEL_ROWS; i++)
		level_map[i] = lv->cells[i];

	hal_ppu_write(PPU_CTRL, 0);                 // blank while the map is rebuilt
	set_night(lv->night);
	clear_map();
	draw_hud_labels();
	cam_x = 0;
	for (loaded_cols = 0; loaded_cols < 18; loaded_cols++)
		draw_column(loaded_cols);

	hx = FX(lv->start * 16);
	hy = FX(LEVEL_H - 4 * 16);
	hvx = hvy = 0;
	h_ground = 0;
	h_facing_left = 0;
	for (int i = 0; i < MAX_SLIMES; i++) slimes[i].state = 0;
	for (int i = 0; i < 64; i++) spawned[i] = 0;
	for (int i = 0; i < MAX_POPS; i++) pops[i].timer = 0;
	time_left = 400;
	time_tick = 0;
	mode = M_PLAY;
#ifdef GAME_HOST
	extern int host_start_col;
	if (host_start_col) {
		hx = FX(host_start_col * 16);
		cam_x = host_start_col * 16 - 112 > 0 ? host_start_col * 16 - 112 : 0;
		if (cam_x > lv->width * 16 - 256) cam_x = lv->width * 16 - 256;
		for (int c = cam_x >> 4; c < (cam_x >> 4) + 18; c++)
			draw_column(c);
		loaded_cols = (cam_x >> 4) + 18;
		for (int i = 0; i < lv->n_enemies; i++)
			spawned[i] = lv->enemies[i] * 16 < cam_x + 256 + 16;
	}
#endif
	draw_hud();
	hal_ppu_write(PPU_SCROLL_X, cam_x & 511);
	hal_ppu_write(PPU_CTRL, PPU_CTRL_BG | PPU_CTRL_SPR);
}

static void scroll_camera(void)
{
	int32_t want = PX(hx) - 112;                // keep the hero left of centre
	int32_t max = lv->width * 16 - 256;
	if (want > max) want = max;
	if (want > cam_x) cam_x = want;
	while (loaded_cols < lv->width && loaded_cols < (cam_x >> 4) + 18)
		draw_column(loaded_cols++);
}

// --- hero ----------------------------------------------------------------------------

static void add_score(uint32_t points)
{
	score += points;
	if (score > 999999) score = 999999;
}

static void pop_coin(int col, int row)
{
	for (int i = 0; i < MAX_POPS; i++) {
		if (pops[i].timer == 0) {
			pops[i].x = col * 16;
			pops[i].y = row * 16 - 16;
			pops[i].timer = 24;
			break;
		}
	}
	coins++;
	add_score(200);
}

static void hit_block_from_below(int32_t px, int32_t py)
{
	int col = px >> 4, row = py >> 4;
	int b = block_at(px, py);
	if (b == BLK_QUESTION) {
		set_block(col, row, BLK_USED);
		pop_coin(col, row);
	} else if (b == BLK_BRICK) {
		set_block(col, row, BLK_SKY);
		add_score(50);
	}
	// a slime standing on the block is knocked off
	for (int i = 0; i < MAX_SLIMES; i++) {
		struct slime *s = &slimes[i];
		if (s->state == 1 && PX(s->x) + 16 > col * 16 && PX(s->x) < col * 16 + 16 &&
		    PX(s->y) + 16 >= row * 16 - 2 && PX(s->y) + 16 <= row * 16 + 2) {
			s->state = 0;
			add_score(100);
		}
	}
}

static void collect_coins(void)
{
	int32_t x = PX(hx), y = PX(hy);
	static const int8_t pts[4][2] = {{3, 3}, {12, 3}, {3, 14}, {12, 14}};
	for (int i = 0; i < 4; i++) {
		int px = x + pts[i][0], py = y + pts[i][1];
		if (block_at(px, py) == BLK_COIN) {
			set_block(px >> 4, py >> 4, BLK_SKY);
			coins++;
			add_score(200);
		}
	}
	if (coins >= 100) {
		coins -= 100;
		lives++;
	}
}

static void kill_hero(void)
{
	if (mode != M_PLAY)
		return;
	mode = M_DYING;
	mode_timer = 0;
	hvy = -0x500;
	hvx = 0;
}

static void move_hero(uint8_t b)
{
	int run = b & BTN_B;
	int32_t max = run ? MAX_RUN : MAX_WALK;
	int32_t accel = run ? ACCEL_RUN : ACCEL_WALK;

	// horizontal speed
	if (b & BTN_RIGHT) {
		hvx += hvx < 0 ? SKID : accel;
		if (hvx > max) hvx -= FRICTION;
		if (hvx > max + FRICTION) hvx = max;
		h_facing_left = 0;
	} else if (b & BTN_LEFT) {
		hvx -= hvx > 0 ? SKID : accel;
		if (hvx < -max) hvx += FRICTION;
		if (hvx < -max - FRICTION) hvx = -max;
		h_facing_left = 1;
	} else if (h_ground) {
		if (hvx > FRICTION) hvx -= FRICTION;
		else if (hvx < -FRICTION) hvx += FRICTION;
		else hvx = 0;
	}

	// jump: holding A keeps gravity low while rising
	if ((b & BTN_A) && h_ground && !h_jump_held) {
		hvy = -JUMP_SPEED - ((hvx > MAX_WALK || hvx < -MAX_WALK) ? JUMP_RUN_BONUS : 0);
		h_ground = 0;
	}
	h_jump_held = (b & BTN_A) != 0;
	hvy += (hvy < 0 && (b & BTN_A)) ? GRAVITY_HOLD : GRAVITY;
	if (hvy > MAX_FALL) hvy = MAX_FALL;

	// move and collide: x first, then y. Hero box: x+3..x+12, y+2..y+15
	hx += hvx;
	int32_t x = PX(hx), y = PX(hy);
	if (x < cam_x) {                            // the camera never goes back
		x = cam_x;
		hx = FX(x);
		if (hvx < 0) hvx = 0;
	}
	if (hvx > 0 && (solid_at(x + 12, y + 2) || solid_at(x + 12, y + 9) || solid_at(x + 12, y + 15))) {
		x = ((x + 12) & ~15) - 13;
		hx = FX(x);
		hvx = 0;
	} else if (hvx < 0 && (solid_at(x + 3, y + 2) || solid_at(x + 3, y + 9) || solid_at(x + 3, y + 15))) {
		x = ((x + 3) | 15) - 2;
		hx = FX(x);
		hvx = 0;
	}

	hy += hvy;
	y = PX(hy);
	h_ground = 0;
	if (hvy >= 0) {
		if (solid_at(x + 4, y + 16) || solid_at(x + 11, y + 16)) {
			y = ((y + 16) & ~15) - 16;
			hy = FX(y);
			hvy = 0;
			h_ground = 1;
		}
	} else if (solid_at(x + 7, y + 2) || solid_at(x + 8, y + 2)) {
		hit_block_from_below(x + 8, y + 2);
		y = ((y + 2) | 15) - 1;
		hy = FX(y);
		hvy = 0;
	}

	collect_coins();

	if (y > LEVEL_H)
		kill_hero();

	// reached the pole? (anywhere along the hero's front edge)
	int pole = 0;
	for (int dy = 2; dy < 16; dy += 6) {
		int bk = block_at(x + 12, y + dy);
		pole |= bk == BLK_POLE || bk == BLK_POLE_TOP;
	}
	if (pole) {
		mode = M_CLEAR;
		mode_timer = 0;
		add_score(y < 64 ? 5000 : y < 128 ? 2000 : 500);
		hvx = 0;
	}

	if (h_ground && hvx != 0)
		h_anim += hvx > 0 ? hvx : -hvx;
}

static void draw_hero(void)
{
	int tile;
	if (mode == M_DYING)
		tile = SPR_HERO_DEAD;
	else if (!h_ground)
		tile = SPR_HERO_JUMP;
	else if (hvx == 0)
		tile = SPR_HERO_STAND;
	else
		tile = (h_anim >> 11) & 1 ? SPR_HERO_WALK1 : SPR_HERO_WALK2;
	sprite(PX(hx), PX(hy), tile, h_facing_left);
}

// --- slimes ------------------------------------------------------------------------------

static void spawn_slimes(void)
{
	for (int i = 0; i < lv->n_enemies && i < 64; i++) {
		if (spawned[i] || lv->enemies[i] * 16 > cam_x + 256 + 16)
			continue;
		spawned[i] = 1;
		for (int j = 0; j < MAX_SLIMES; j++) {
			if (slimes[j].state == 0) {
				slimes[j].x = FX(lv->enemies[i] * 16);
				slimes[j].y = FX(LEVEL_H - 3 * 16);
				slimes[j].vx = -SLIME_SPEED;
				slimes[j].vy = 0;
				slimes[j].state = 1;
				break;
			}
		}
	}
}

static void update_slimes(void)
{
	int32_t px = PX(hx), py = PX(hy);

	for (int i = 0; i < MAX_SLIMES; i++) {
		struct slime *s = &slimes[i];
		if (s->state == 2) {
			if (--s->timer == 0) s->state = 0;
			continue;
		}
		if (s->state != 1)
			continue;

		int32_t x = PX(s->x);
		if (x < cam_x - 64) {                   // left behind for good
			s->state = 0;
			continue;
		}

		s->x += s->vx;
		x = PX(s->x);
		int32_t y = PX(s->y);
		if (s->vx < 0 && (solid_at(x + 1, y + 8) || x < 0)) {
			s->vx = SLIME_SPEED;
		} else if (s->vx > 0 && solid_at(x + 14, y + 8)) {
			s->vx = -SLIME_SPEED;
		}

		s->vy += GRAVITY;
		if (s->vy > MAX_FALL) s->vy = MAX_FALL;
		s->y += s->vy;
		y = PX(s->y);
		if (solid_at(x + 3, y + 16) || solid_at(x + 12, y + 16)) {
			s->y = FX(((y + 16) & ~15) - 16);
			s->vy = 0;
		}
		if (y > LEVEL_H) {
			s->state = 0;
			continue;
		}

		// against the hero
		if (mode == M_PLAY && px + 12 > x + 2 && px + 3 < x + 14 && py + 15 > y + 6 && py + 2 < y + 16) {
			if (hvy > 0 && py + 15 < y + 12) {
				s->state = 2;
				s->timer = 30;
				hvy = -BOUNCE;
				add_score(100);
			} else {
				kill_hero();
			}
		}
	}
}

static void draw_slimes(void)
{
	for (int i = 0; i < MAX_SLIMES; i++) {
		struct slime *s = &slimes[i];
		if (s->state == 1)
			sprite(PX(s->x), PX(s->y), (frame >> 3) & 1 ? SPR_SLIME_1 : SPR_SLIME_2, s->vx > 0);
		else if (s->state == 2)
			sprite(PX(s->x), PX(s->y), SPR_SLIME_FLAT, 0);
	}
}

static void draw_pops(void)
{
	for (int i = 0; i < MAX_POPS; i++) {
		if (pops[i].timer) {
			pops[i].timer--;
			pops[i].y -= pops[i].timer > 12 ? 3 : -2;
			sprite(pops[i].x, pops[i].y, SPR_COIN_SPIN, (frame >> 2) & 1);
		}
	}
}

static void draw_flag(void)
{
	for (int col = cam_x >> 4; col < (cam_x >> 4) + 17 && col < lv->width; col++)
		if (level_map[col * LEVEL_ROWS + 1] == BLK_POLE_TOP)
			sprite(col * 16 - 8, 2 * 16 + (mode == M_CLEAR ? mode_timer < 96 ? mode_timer : 96 : 0), SPR_FLAG, 1);
}

// --- screens ---------------------------------------------------------------------------------

static void title_screen(void)
{
	level_no = 0;
	lv = &game_levels[0];
	for (int i = 0; i < lv->width * LEVEL_ROWS; i++)
		level_map[i] = lv->cells[i];
	hal_ppu_write(PPU_CTRL, 0);
	set_night(0);
	clear_map();
	draw_hud_labels();
	cam_x = 0;
	for (int c = 0; c < 18; c++)
		draw_column(c);
	text(8, 5, "NANDTIER  HOPPER");
	text(7, 9, "RUN, JUMP AND STOMP");
	text(5, 10, "YOUR WAY TO THE FLAG!");
	text(4, 16, "A/D OR ARROWS  MOVE");
	text(4, 17, "SPACE OR K     JUMP");
	text(4, 18, "J              RUN");
	text(4, 19, "Q              QUIT");
	text(10, 23, "TOP");
	number(14, 23, best, 6);
	score = 0; coins = 0; lives = 3; time_left = 400;
	draw_hud();
	hal_ppu_write(PPU_SCROLL_X, 0);
	hal_ppu_write(PPU_CTRL, PPU_CTRL_BG | PPU_CTRL_SPR);
	mode = M_TITLE;
	mode_timer = 0;
}

static void message(const char *s)
{
	int len = 0;
	while (s[len]) len++;
	// tile map columns that are on screen now
	int col = ((cam_x >> 3) + 16 - len / 2) & 63;
	for (int i = 0; i < len; i++)
		if (s[i] != ' ')                        // leave the picture between words
			set_tile((col + i) & 63, 12, s[i] - 0x20);
}

void game_run(void)
{
	load_graphics();
	hal_ppu_write(PPU_SPLIT, HUD_LINES);
	hal_ppu_write(PPU_SCROLL_Y, 0);
	quit = 0;
	game_slowest_frame = 0;
	uint32_t frame_start = hal_cycles();
	title_screen();

	while (!quit) {
		read_input();
		uint8_t b = buttons();

		switch (mode) {
		case M_TITLE:
			if (++mode_timer > 20 && (b & (BTN_START | BTN_A))) {
				level_no = 0;
#ifdef GAME_HOST
				extern int host_start_level;
				level_no = host_start_level;
#endif
				start_level();
			} else
				text(10, 21, (mode_timer >> 5) & 1 ? "           " : "PRESS START");
			break;

		case M_PLAY:
			spawn_slimes();
			move_hero(b);
			update_slimes();
			scroll_camera();
			if (++time_tick == 24) {
				time_tick = 0;
				if (--time_left == 0)
					kill_hero();
			}
			break;

		case M_DYING:
			// fall off the screen, then try again
			if (++mode_timer > 20) {
				hvy += GRAVITY;
				hy += hvy;
			}
			if (mode_timer == 150) {
				if (--lives == 0) {
					mode = M_GAME_OVER;
					mode_timer = 0;
					message("GAME OVER");
				} else
					start_level();
			}
			break;

		case M_CLEAR:
			// slide down the pole, then walk off to the right
			mode_timer++;
			if (PX(hy) < LEVEL_H - 3 * 16) {
				hy += FX(2);
			} else {
				h_ground = 1;
				hvx = MAX_WALK;
				hx += hvx;
				h_anim += hvx;
			}
			if (mode_timer == 60)
				message("COURSE CLEAR!");
			if (time_left > 0 && mode_timer > 60) {
				time_left--;
				add_score(10);
			}
			if (mode_timer > 240 && time_left == 0) {
				if (++level_no == NUM_LEVELS) {
					mode = M_WIN;
					mode_timer = 0;
					message("YOU WIN! THANKS FOR PLAYING");
				} else
					start_level();
			}
			break;

		case M_GAME_OVER:
		case M_WIN:
			if (++mode_timer > 240 || (mode_timer > 60 && (b & BTN_START))) {
				if (score > best) best = score;
				title_screen();
			}
			break;

		default:
			break;
		}

		if (mode != M_TITLE) {
			if (mode != M_GAME_OVER && mode != M_WIN)
				draw_hero();
			draw_slimes();
			draw_pops();
		}
		if (mode != M_GAME_OVER && mode != M_WIN)
			draw_flag();

		// everything below goes to the PPU in the vertical blank
		uint32_t busy = hal_cycles() - frame_start;
		if (busy > game_slowest_frame && mode == M_PLAY)
			game_slowest_frame = busy;
		wait_frame();
		frame_start = hal_cycles();
		upload_sprites();
		hal_ppu_write(PPU_SCROLL_X, cam_x & 511);
		draw_hud();
	}

	if (score > best) best = score;
	hal_ppu_write(PPU_CTRL, PPU_CTRL_TERM);
}

#ifdef GAME_HOST
#include <stdio.h>

// test/host/game_host.c prints this when it stops the game
void game_report(void)
{
	printf("frame %u: mode %d, level %d, hero x %d y %d, camera %d, score %u, coins %d, lives %d, time %d\n",
	       (unsigned)frame, mode, level_no, (int)PX(hx), (int)PX(hy), (int)cam_x,
	       (unsigned)score, coins, lives, time_left);
}
#endif
