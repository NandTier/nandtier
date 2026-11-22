// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Runs the platformer (fw/games/hopper/game.c) on a PC against the PPU
// model (ppu_model.c).
//
//   game_host <frames> <out prefix> [<frame>,...] [script] [gfx pack]
//
//   GAME_START_LEVEL, GAME_START_COL: start in this level, at this column

#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "game.h"
#include "game_hal.h"
#include "nandtier.h"
#include "ppu_model.h"

static const char *gfx_pack;
int host_start_col;             // GAME_START_COL: start the hero at this level column
int host_start_level;           // GAME_START_LEVEL: 0 = first level

int hal_load_sd_graphics(void)
{
	if (!gfx_pack)
		return -1;
	FILE *f = fopen(gfx_pack, "rb");
	unsigned char block[512];
	if (!f || fread(block, 1, 512, f) != 512 || memcmp(block, "NTGFX1", 6)) {
		fprintf(stderr, "game_host: %s is not a graphics pack\n", gfx_pack);
		exit(1);
	}
	for (int i = 0; i < 2048; i++) {
		unsigned char w[4];
		if (fread(w, 1, 4, f) != 4) exit(1);
		hal_ppu_write(PPU_CHR + i * 4, w[0] | w[1] << 8 | w[2] << 16 | (uint32_t)w[3] << 24);
	}
	for (int i = 0; i < 128; i++) {
		unsigned char w[2];
		if (fread(w, 1, 2, f) != 2) exit(1);
		hal_ppu_write(PPU_PALETTE + i * 4, w[0] | w[1] << 8);
	}
	fclose(f);
	return 0;
}

int main(int argc, char **argv)
{
	ppu_model_args(argc, argv);
	if (argc > 5 && argv[5][0])
		gfx_pack = argv[5];
	if (getenv("GAME_START_LEVEL"))
		host_start_level = atoi(getenv("GAME_START_LEVEL"));
	if (getenv("GAME_START_COL"))
		host_start_col = atoi(getenv("GAME_START_COL"));
	game_run();
	return 0;
}
