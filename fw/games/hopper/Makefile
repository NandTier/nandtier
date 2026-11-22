# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# NandTier Hopper cartridge. Also writes build/game_gfx.bin, the game's
# graphics as an optional SD card pack (see assets/gen_assets.py).

NAME     = hopper
SRCS     = main.c game.c game_assets.c sd.c
NO_NGAME = 1

include ../../sdk/cart.mk

all: $(BUILD)/game_gfx.bin

# graphics and levels: C data, plus the SD card graphics pack
game_assets.c game_assets.h $(BUILD)/game_gfx.bin &: assets/gen_assets.py assets/art.py assets/levels.py \
		../../../hw/video/gen_font.py | $(BUILD)
	$(PYTHON_NAME) assets/gen_assets.py game_assets.c game_assets.h $(BUILD)/game_gfx.bin

$(BUILD)/game.c.o $(BUILD)/main.c.o: game_assets.h
