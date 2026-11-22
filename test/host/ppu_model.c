// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Software model of the NandTier PPU (the rules in hw/video/nt_ppu.v) with
// a scripted controller and screenshots, for running the games on a PC
// (fw/sdk/game_hal.h, built with GAME_HOST). See ppu_model.h.

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "game_hal.h"
#include "nandtier.h"
#include "ppu_model.h"

static uint16_t pal[128];
static uint32_t oam[64];
static uint16_t nt[2048];
static uint32_t chr[2048];
static uint32_t ctrl = PPU_CTRL_TERM, scroll_x, scroll_y, split;

void hal_ppu_write(uint32_t off, uint32_t v)
{
	if (off < 0x400) {
		switch (off) {
		case PPU_CTRL:     ctrl = v & 7; break;
		case PPU_SCROLL_X: scroll_x = v & 511; break;
		case PPU_SCROLL_Y: scroll_y = v & 255; break;
		case PPU_SPLIT:    split = v & 255; break;
		}
	} else if (off >= PPU_PALETTE && off < PPU_PALETTE + 0x200) {
		pal[(off - PPU_PALETTE) / 4] = v & 0xFFF;
	} else if (off >= PPU_OAM && off < PPU_OAM + 0x100) {
		oam[(off - PPU_OAM) / 4] = v;
	} else if (off >= PPU_NAMETAB && off < PPU_NAMETAB + 0x2000) {
		nt[(off - PPU_NAMETAB) / 4] = v & 0xFFF;
	} else if (off >= PPU_CHR && off < PPU_CHR + 0x2000) {
		chr[(off - PPU_CHR) / 4] = v;
	} else {
		fprintf(stderr, "game_host: PPU write to bad offset 0x%x\n", off);
		exit(1);
	}
}

// --- model of the picture ---------------------------------------------------------

static uint16_t render_pixel(int px, int py)
{
	int sxs = py < (int)split ? 0 : (int)scroll_x;
	int sys = py < (int)split ? py : (py + (int)scroll_y) & 255;
	int mapx = (px + sxs) & 511;
	uint16_t e = nt[(sys >> 3) * 64 + (mapx >> 3)];
	int trow = (e & 0x800) ? 7 - (sys & 7) : sys & 7;
	int k = (e & 0x400) ? 7 - (mapx & 7) : mapx & 7;
	int bgc = (chr[(e & 0xFF) * 8 + trow] >> (4 * k)) & 15;
	if (!(ctrl & PPU_CTRL_BG)) bgc = 0;

	int found[16], n = 0;
	for (int i = 0; i < 64 && n < 16; i++) {
		int y = oam[i] & 0xFF, h = (oam[i] >> 29) & 1 ? 16 : 8;
		if (py >= y && py - y < h) found[n++] = i;
	}
	int best = -1, best_c = 0;
	for (int s = n - 1; s >= 0; s--) {
		uint32_t o = oam[found[s]];
		int w = (o >> 29) & 1 ? 16 : 8;
		int x = (o >> 8) & 0x1FF;
		if (x & 0x100) x -= 512;
		int dx = px - x;
		if (dx < 0 || dx >= w) continue;
		int r = py - (int)(o & 0xFF);
		if ((o >> 28) & 1) r = w - 1 - r;
		int half = dx >> 3, hf = (o >> 27) & 1;
		int col = w == 16 ? (hf ? 1 - half : half) : 0;
		int tile = (((o >> 17) & 0xFF) + (r >= 8 ? 16 : 0) + col) & 255;
		int kk = hf ? 7 - (dx & 7) : dx & 7;
		int c = (chr[tile * 8 + (r & 7)] >> (4 * kk)) & 15;
		if (c) { best = found[s]; best_c = c; }
	}
	int idx = bgc ? ((e >> 8) & 3) * 16 + bgc : 0;
	if (best >= 0 && (ctrl & PPU_CTRL_SPR)) {
		uint32_t o = oam[best];
		if (!((o >> 30) & 1) || !bgc)
			return pal[64 + ((o >> 25) & 3) * 16 + best_c];
	}
	return pal[idx];
}

static void save_frame(const char *prefix, int f)
{
	char name[512];
	snprintf(name, sizeof(name), "%s_%04d.ppm", prefix, f);
	FILE *out = fopen(name, "wb");
	if (!out) { perror(name); exit(1); }
	fprintf(out, "P6\n256 240\n255\n");
	for (int y = 0; y < 240; y++)
		for (int x = 0; x < 256; x++) {
			uint16_t c = (ctrl & 3) ? render_pixel(x, y) : 0;
			unsigned char rgb[3] = {((c >> 8) & 15) * 17, ((c >> 4) & 15) * 17, (c & 15) * 17};
			fwrite(rgb, 1, 3, out);
		}
	fclose(out);
}

// --- frames, input -------------------------------------------------------------------

static int frames, frame, status_reads;
static const char *prefix;
static int shots[64], n_shots;
static struct { int from, to, buttons; } script[64];
static int n_script;
static int sent_frame = -1, sent_quit;
static FILE *uart_out;                  // NG_UART_OUT

uint32_t hal_ppu_read(uint32_t off)
{
	if (off != PPU_STATUS)
		return 0;
	// the game reads STATUS twice per frame: every second read ends a frame
	if (++status_reads % 2 == 0) {
		frame++;
		for (int i = 0; i < n_shots; i++)
			if (shots[i] == frame)
				save_frame(prefix, frame);
		if (frame >= frames) {
			game_report();
			if (uart_out)
				fclose(uart_out);
			exit(0);
		}
	}
	return (uint32_t)status_reads << 16;
}

// UART traffic (NG_UART_IN / NG_UART_OUT, see ppu_model.h)
static struct { int frame; uint8_t byte; } uart_in[65536];
static int n_uart_in, next_uart_in;

static void load_uart_in(const char *path)
{
	FILE *f = fopen(path, "r");
	if (!f) { perror(path); exit(1); }
	char line[8192];
	while (fgets(line, sizeof(line), f)) {
		char *p = line, *end;
		long frame = strtol(p, &end, 10);
		if (end == p)
			continue;
		for (p = end;;) {
			long b = strtol(p, &end, 16);
			if (end == p || n_uart_in == 65536)
				break;
			uart_in[n_uart_in].frame = (int)frame;
			uart_in[n_uart_in++].byte = (uint8_t)b;
			p = end;
		}
	}
	fclose(f);
}

void hal_uart_put(uint8_t b)
{
	if (uart_out)
		fputc(b, uart_out);
}

// one controller byte per frame; a script entry with button bit 8 also
// types 'q' (quit) in that frame; then the UART bytes due by this frame
int hal_key(void)
{
	int b = 0;
	for (int i = 0; i < n_script; i++)
		if (frame >= script[i].from && frame <= script[i].to)
			b |= script[i].buttons;
	if (sent_frame != frame) {
		sent_frame = frame;
		sent_quit = 0;
		return 0x80 | (b & 0x7F);
	}
	if ((b & 0x100) && !sent_quit) {
		sent_quit = 1;
		return 'q';
	}
	if (next_uart_in < n_uart_in && uart_in[next_uart_in].frame <= frame)
		return uart_in[next_uart_in++].byte;
	return -1;
}

int ppu_model_frame(void)
{
	return frame;
}

uint32_t hal_frame_count(void)
{
	return frame;
}

void ppu_model_args(int argc, char **argv)
{
	if (argc < 3) {
		fprintf(stderr, "usage: %s <frames> <out prefix> [frames,...] [script] ...\n", argv[0]);
		exit(1);
	}
	frames = atoi(argv[1]);
	prefix = argv[2];
	if (argc > 3) {
		for (char *p = strtok(argv[3], ","); p && n_shots < 64; p = strtok(NULL, ","))
			shots[n_shots++] = atoi(p);
	}
	if (getenv("NG_UART_IN"))
		load_uart_in(getenv("NG_UART_IN"));
	if (getenv("NG_UART_OUT")) {
		uart_out = fopen(getenv("NG_UART_OUT"), "wb");
		if (!uart_out) { perror(getenv("NG_UART_OUT")); exit(1); }
	}
	if (argc > 4) {
		for (char *p = strtok(argv[4], ";"); p && n_script < 64; p = strtok(NULL, ";")) {
			if (sscanf(p, "%d-%d:%d", &script[n_script].from, &script[n_script].to,
			           &script[n_script].buttons) == 3)
				n_script++;
		}
	}
}

