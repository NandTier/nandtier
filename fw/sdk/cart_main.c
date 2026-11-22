// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Entry of an ngame cartridge: the game's game_main(), then back to the
// launcher.

#include "ngame.h"

void game_main(void);

int main(void)
{
	game_main();
	ng_exit();
}
