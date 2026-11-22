// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// SD card access in SPI mode through the NandTier SD SPI port.
// SDHC/SDXC cards (block addressing, 512-byte blocks) are supported.

#ifndef SD_H
#define SD_H

#include <stdint.h>

#define SD_BLOCK_SIZE 512

// Initialise the card. Returns 0 on success, otherwise:
//   0x1n  CMD0 (go idle) failed, n = low bits of the card's answer
//   0x2n  CMD8 (interface condition) failed
//   0x30  CMD8 echo wrong; r7[0], r7[1] hold the two echo bytes
//   0x4n  CMD55 failed
//   0x05  ACMD41 did not finish (card never left the idle state)
//   0x6n  CMD16 (block length) failed
int sd_init(uint8_t r7[2]);

// Read / write one 512-byte block. Return 0 on success, -1 on failure.
int sd_read_block(uint32_t block, uint8_t *buf);
int sd_write_block(uint32_t block, const uint8_t *buf);

#endif
