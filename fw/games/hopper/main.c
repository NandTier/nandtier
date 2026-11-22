// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier Hopper as a game cartridge: started by the launcher, returns to
// its game menu when the player quits.

#include <stdint.h>
#include "nandtier.h"
#include "cart.h"
#include "sd.h"
#include "game.h"

#define SD_GFX_BLOCK    2048            // graphics pack (optional), see assets/gen_assets.py

static uint8_t sd_buffer[SD_BLOCK_SIZE];

// Graphics pack: block 0 header "NTGFX1", blocks 1-16 the 2048 CHR words,
// block 17 the palette.
int hal_load_sd_graphics(void)
{
	static const char magic[6] = "NTGFX1";
	uint8_t r7[2];

	if (sd_init(r7) || sd_read_block(SD_GFX_BLOCK, sd_buffer))
		return -1;
	for (int i = 0; i < 6; i++)
		if (sd_buffer[i] != (uint8_t)magic[i])
			return -1;
	for (int b = 0; b < 17; b++) {
		if (sd_read_block(SD_GFX_BLOCK + 1 + b, sd_buffer))
			return -1;
		if (b < 16) {
			for (int i = 0; i < 128; i++) {
				const uint8_t *w = &sd_buffer[i * 4];
				PPU_REG(PPU_CHR + (b * 128 + i) * 4) =
					w[0] | w[1] << 8 | w[2] << 16 | (uint32_t)w[3] << 24;
			}
		} else {
			for (int i = 0; i < 128; i++)
				PPU_REG(PPU_PALETTE + i * 4) = sd_buffer[i * 2] | sd_buffer[i * 2 + 1] << 8;
		}
	}
	return 0;
}

int main(void)
{
	game_run();
	cart_exit(game_slowest_frame);
}
