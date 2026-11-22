// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Game cartridges: read the cartridge pack on the SD card (sw/mkcarts.py),
// copy a game into the cartridge slot of the SPI flash and start it there.

#ifndef LOADER_H
#define LOADER_H

#include <stdint.h>

struct cart {
	char     name[17];
	uint32_t block;                 // first SD block of the image
	uint32_t size;                  // bytes
	uint32_t crc;                   // CRC-32 of the image
};

#define LOADER_NO_CARD      -1      // SD card did not initialise
#define LOADER_NO_PACK      -2      // no cartridge pack on the card
#define LOADER_READ_ERROR   -3      // SD read failed
#define LOADER_BAD_CART     -4      // image does not fit the cartridge slot
#define LOADER_VERIFY_ERROR -5      // the flash does not hold the image afterwards

// Read the pack's directory. Returns the number of games (up to max) or
// LOADER_NO_CARD / LOADER_NO_PACK / LOADER_READ_ERROR.
int loader_read_dir(struct cart *carts, int max);

// Is this game in the cartridge slot already?
int loader_installed(const struct cart *c);

// Copy the game into the cartridge slot unless it is there already, and
// check it. progress(done, total) is called as it goes. Returns 1 if it was
// installed already, 0 if it was copied, or a LOADER_ error.
int loader_install(const struct cart *c, void (*progress)(uint32_t done, uint32_t total));

// Start the game in the cartridge slot (number `index` in the directory).
void loader_start(int index) __attribute__((noreturn));

const char *loader_error(int code);

// Flash address where the CPU's address 0 is (the board's FLASH_OFFSET).
uint32_t loader_flash_base(void);

uint32_t crc32(const void *data, uint32_t len);

#endif
