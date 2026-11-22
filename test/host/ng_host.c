// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Runs an ngame cartridge (fw/games/<game>, fw/sdk/ngame.h) on a PC
// against the PPU model (ppu_model.c).
//
//   ng_host <frames> <out prefix> [<frame>,...] [script]
//
// Prints the game's report (game_report) when the frames are done, or
// "quit" and the report when the game leaves.

#include <stdio.h>
#include <stdlib.h>
#include "ppu_model.h"

void game_main(void);

void host_exit(void)
{
	printf("quit at frame %d\n", ppu_model_frame());
	game_report();
	fflush(NULL);
	exit(0);
}

int main(int argc, char **argv)
{
	ppu_model_args(argc, argv);
	game_main();
	host_exit();
}
