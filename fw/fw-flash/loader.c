// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Game cartridge loader. The SPI flash is written with the boot ROM's
// flash_io() (nt_flash_io), which runs from the boot RAM while the flash is
// out of execute-in-place mode; switching XIP back on afterwards empties
// the flash cache, so the CPU sees the new contents.
//
// flash_io() takes flash addresses, the CPU sees the flash from the board's
// FLASH_OFFSET on (hw/nandtier.v: 0 on the Tang Nano 9K, further up where
// the bitstream is in the same flash). loader_flash_base() finds it by
// looking for the launcher's own first bytes, so the same firmware runs on
// every board.
//
// Cartridge pack on the SD card, from block NT_CART_SD_BLOCK (sw/mkcarts.py):
//
//   block 0, the directory:
//     0   "NTCART1\0"
//     8   number of games (little-endian 32-bit)
//     12  sum of the 32-bit words at 16..511
//     16  15 entries of 32 bytes:
//           0  name, 16 bytes, NUL padded
//           16 first block of the image, from the directory block
//           20 size in bytes
//           24 CRC-32 (as zlib.crc32)
//           28 load address (NT_CART_SLOT)
//   then the images, each starting on a block boundary.

#include "nandtier.h"
#include "sd.h"
#include "loader.h"

#ifdef LOADER_HOST
#include "loader_host.h"        // test/host: models of the flash and the SD card
#else
#define XIP_MEMORY  ((const uint8_t *)NT_FLASH_BASE)
#endif
#define SLOT_MEMORY (XIP_MEMORY + NT_CART_SLOT)

#define FLASH_READ      0x03
#define FLASH_SE        0x20            // 4 KiB sector erase
#define FLASH_PP        0x02            // page program, up to 256 bytes
#define SECTOR          4096
#define PAGE            256

static uint8_t block_buf[SD_BLOCK_SIZE];
static uint8_t page_cmd[4 + PAGE];

static uint32_t get32(const uint8_t *p)
{
	return p[0] | p[1] << 8 | p[2] << 16 | (uint32_t)p[3] << 24;
}

// --- CRC-32 (reflected, polynomial 0xEDB88320), four bits at a time -------------------

static const uint32_t crc_nibble[16] = {
	0x00000000, 0x1DB71064, 0x3B6E20C8, 0x26D930AC, 0x76DC4190, 0x6B6B51F4, 0x4DB26158, 0x5005713C,
	0xEDB88320, 0xF00F9344, 0xD6D6A3E8, 0xCB61B38C, 0x9B64C2B0, 0x86D3D2D4, 0xA00AE278, 0xBDBDF21C,
};

static uint32_t crc_byte(uint32_t crc, uint32_t b)
{
	crc ^= b;
	crc = (crc >> 4) ^ crc_nibble[crc & 15];
	return (crc >> 4) ^ crc_nibble[crc & 15];
}

uint32_t crc32(const void *data, uint32_t len)
{
	uint32_t crc = 0xFFFFFFFF;
	const uint8_t *p = data;

	// whole words where possible: a quarter of the bus accesses
	for (; len >= 4 && ((uint32_t)p & 3) == 0; len -= 4, p += 4) {
		uint32_t w = *(const uint32_t *)p;
		crc = crc_byte(crc, w & 0xFF);
		crc = crc_byte(crc, (w >> 8) & 0xFF);
		crc = crc_byte(crc, (w >> 16) & 0xFF);
		crc = crc_byte(crc, w >> 24);
	}
	for (; len; len--)
		crc = crc_byte(crc, *p++);
	return ~crc;
}

// --- SD card -----------------------------------------------------------------------

int loader_read_dir(struct cart *carts, int max)
{
	static const char magic[8] = "NTCART1";
	uint8_t r7[2];

	if (sd_init(r7))
		return LOADER_NO_CARD;
	if (sd_read_block(NT_CART_SD_BLOCK, block_buf))
		return LOADER_READ_ERROR;
	for (int i = 0; i < 8; i++)
		if (block_buf[i] != (uint8_t)magic[i])
			return LOADER_NO_PACK;

	uint32_t sum = 0;
	for (int i = 16; i < SD_BLOCK_SIZE; i += 4)
		sum += get32(&block_buf[i]);
	uint32_t n = get32(&block_buf[8]);
	if (sum != get32(&block_buf[12]) || n > NT_CART_MAX)
		return LOADER_NO_PACK;

	int count = 0;
	for (uint32_t i = 0; i < n && count < max; i++) {
		const uint8_t *e = &block_buf[16 + i * 32];
		struct cart *c = &carts[count];
		if (get32(&e[28]) != NT_CART_SLOT)
			continue;                       // built for another place: skip
		for (int k = 0; k < 16; k++)
			c->name[k] = e[k];
		c->name[16] = 0;
		c->block = get32(&e[16]);
		c->size  = get32(&e[20]);
		c->crc   = get32(&e[24]);
		count++;
	}
	return count;
}

// --- SPI flash ---------------------------------------------------------------------

#define PROBE_LEN 64

uint32_t loader_flash_base(void)
{
	static const uint32_t candidates[] = {
		0x000000, 0x100000, 0x200000, 0x300000, 0x400000, 0x600000, 0x800000
	};
	static uint32_t base = 0xFFFFFFFF;
	uint8_t mine[PROBE_LEN], cmd[4 + PROBE_LEN];

	if (base != 0xFFFFFFFF)
		return base;
	for (int i = 0; i < PROBE_LEN; i++)
		mine[i] = XIP_MEMORY[i];            // the launcher's first bytes, through XIP
	base = 0;
	for (unsigned c = 0; c < sizeof(candidates) / sizeof(candidates[0]); c++) {
		uint32_t a = candidates[c];
		cmd[0] = FLASH_READ;
		cmd[1] = a >> 16;
		cmd[2] = a >> 8;
		cmd[3] = a;
		for (int i = 0; i < PROBE_LEN; i++)
			cmd[4 + i] = 0;
		nt_flash_io(cmd, 4 + PROBE_LEN, 0);
		int same = 1;
		for (int i = 0; i < PROBE_LEN; i++)
			same &= cmd[4 + i] == mine[i];
		if (same) {
			base = a;
			break;
		}
	}
	return base;
}

static void flash_erase_sector(uint32_t addr)
{
	uint8_t cmd[4] = {FLASH_SE, addr >> 16, addr >> 8, addr};
	nt_flash_io(cmd, 4, 1);
}

static void flash_program_page(uint32_t addr, const uint8_t *data)
{
	int blank = 1;
	for (int i = 0; i < PAGE; i++)
		blank &= data[i] == 0xFF;
	if (blank)                              // erased already
		return;
	page_cmd[0] = FLASH_PP;
	page_cmd[1] = addr >> 16;
	page_cmd[2] = addr >> 8;
	page_cmd[3] = addr;
	for (int i = 0; i < PAGE; i++)
		page_cmd[4 + i] = data[i];
	nt_flash_io(page_cmd, 4 + PAGE, 1);     // overwrites page_cmd
}

int loader_installed(const struct cart *c)
{
	return c->size && c->size <= NT_CART_SLOT_SIZE &&
	       crc32(SLOT_MEMORY, c->size) == c->crc;
}

int loader_install(const struct cart *c, void (*progress)(uint32_t done, uint32_t total))
{
	if (c->size == 0 || c->size > NT_CART_SLOT_SIZE)
		return LOADER_BAD_CART;
	if (loader_installed(c))
		return 1;

	uint32_t slot    = loader_flash_base() + NT_CART_SLOT;
	uint32_t sectors = (c->size + SECTOR - 1) / SECTOR;
	uint32_t blocks  = (c->size + SD_BLOCK_SIZE - 1) / SD_BLOCK_SIZE;
	uint32_t total   = sectors + blocks;

	for (uint32_t s = 0; s < sectors; s++) {
		flash_erase_sector(slot + s * SECTOR);
		if (progress)
			progress(s + 1, total);
	}
	for (uint32_t b = 0; b < blocks; b++) {
		if (sd_read_block(NT_CART_SD_BLOCK + c->block + b, block_buf))
			return LOADER_READ_ERROR;
		uint32_t addr = slot + b * SD_BLOCK_SIZE;
		flash_program_page(addr, block_buf);
		flash_program_page(addr + PAGE, block_buf + PAGE);
		if (progress)
			progress(sectors + b + 1, total);
	}
	return loader_installed(c) ? 0 : LOADER_VERIFY_ERROR;
}

#ifndef LOADER_HOST
void loader_start(int index)
{
	PPU_REG(PPU_CTRL) = 0;                  // the game sets the screen up
	nt_handoff_set(NT_HANDOFF_PLAY, index);
	((void (*)(void))NT_CART_SLOT)();
	__builtin_unreachable();
}
#endif

const char *loader_error(int code)
{
	switch (code) {
	case LOADER_NO_CARD:      return "NO SD CARD";
	case LOADER_NO_PACK:      return "NO GAMES ON THE SD CARD";
	case LOADER_READ_ERROR:   return "SD CARD READ ERROR";
	case LOADER_BAD_CART:     return "GAME TOO BIG FOR THE SLOT";
	case LOADER_VERIFY_ERROR: return "FLASH VERIFY FAILED";
	default:                  return "ERROR";
	}
}
