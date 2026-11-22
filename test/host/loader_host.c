// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// The cartridge loader (fw/fw-flash/loader.c) on a PC, against models of
// the SPI flash (erase sets bytes to FF, programming can only clear bits)
// and of the SD card (an image file).
//
//   loader_host <sd image> <flash out> list
//   loader_host <sd image> <flash out> install <n> [<n> ...]
//
// The flash starts erased, or with <flash out> if that exists, and is
// saved there at the end. LOADER_XIP_OFFSET=<n>: the CPU sees the flash
// from address n on (the board's FLASH_OFFSET); then a launcher image
// (LOADER_LAUNCHER=<file>) is put there for the loader to find.

#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include "nandtier.h"
#include "sd.h"
#include "loader.h"
#include "loader_host.h"

#define FLASH_SIZE (4 << 20)

uint8_t  host_flash[FLASH_SIZE];
uint32_t host_xip_offset;
static FILE *sd;
static int erases, programs, reads, flash_errors;

void host_flash_io(uint8_t *buf, int len, int wren)
{
	uint32_t a = buf[1] << 16 | buf[2] << 8 | buf[3];
	if (!wren) {
		if (buf[0] == 0x03 && len >= 4) {           // read
			for (int i = 4; i < len; i++)
				buf[i] = host_flash[(a + i - 4) % FLASH_SIZE];
			reads++;
		} else {
			flash_errors++;
		}
		return;
	}
	if (buf[0] == 0x20 && len == 4) {
		if (a & 0xFFF)
			flash_errors++;
		memset(&host_flash[a & ~0xFFFu], 0xFF, 4096);
		erases++;
	} else if (buf[0] == 0x02 && len >= 5 && len <= 260) {
		if ((a & 0xFF) + len - 4 > 256)
			flash_errors++;     // would wrap around inside the page
		for (int i = 0; i < len - 4; i++)
			host_flash[a + i] &= buf[4 + i];
		programs++;
	} else {
		flash_errors++;
	}
	for (int i = 0; i < len; i++)   // the bytes read back: nothing useful
		buf[i] = 0xFF;
}

int sd_init(uint8_t r7[2])
{
	(void)r7;
	return sd ? 0 : 0x10;
}

int sd_read_block(uint32_t block, uint8_t *buf)
{
	if (block < NT_CART_SD_BLOCK)
		return -1;
	memset(buf, 0, SD_BLOCK_SIZE);
	fseek(sd, (long)(block - NT_CART_SD_BLOCK) * SD_BLOCK_SIZE, SEEK_SET);
	if (fread(buf, 1, SD_BLOCK_SIZE, sd) == 0)
		memset(buf, 0, SD_BLOCK_SIZE);   // past the end of the image: an empty card
	return 0;
}

int sd_write_block(uint32_t block, const uint8_t *buf)
{
	(void)block;
	(void)buf;
	return -1;
}

static void progress(uint32_t done, uint32_t total)
{
	static uint32_t last;
	if (done <= last && done != 1)
		flash_errors += 1000;       // progress must only go forward
	last = done == total ? 0 : done;
}

int main(int argc, char **argv)
{
	if (argc < 4) {
		fprintf(stderr, "usage: loader_host <sd image> <flash out> list | install <n>...\n");
		return 1;
	}
	sd = fopen(argv[1], "rb");      // a missing file is a missing card
	memset(host_flash, 0xFF, sizeof(host_flash));
	FILE *f = fopen(argv[2], "rb");
	if (f) {
		if (fread(host_flash, 1, FLASH_SIZE, f) != FLASH_SIZE)
			return 1;
		fclose(f);
	}
	if (getenv("LOADER_XIP_OFFSET"))
		host_xip_offset = strtoul(getenv("LOADER_XIP_OFFSET"), NULL, 0);
	if (getenv("LOADER_LAUNCHER")) {
		f = fopen(getenv("LOADER_LAUNCHER"), "rb");
		if (!f || fread(&host_flash[host_xip_offset], 1, 4096, f) == 0)
			return 1;
		fclose(f);
	}
	printf("base 0x%06x\n", (unsigned)loader_flash_base());

	struct cart carts[NT_CART_MAX];
	int n = loader_read_dir(carts, NT_CART_MAX);
	printf("dir %d\n", n);
	for (int i = 0; i < n; i++)
		printf("cart %d %s size=%u crc=%08x installed=%d\n", i + 1, carts[i].name,
		       (unsigned)carts[i].size, (unsigned)carts[i].crc, loader_installed(&carts[i]));

	if (strcmp(argv[3], "install") == 0) {
		for (int k = 4; k < argc; k++) {
			int i = atoi(argv[k]) - 1;
			erases = programs = 0;
			int r = i >= 0 && i < n ? loader_install(&carts[i], progress) : -99;
			printf("install %d result=%d erases=%d programs=%d errors=%d\n", i + 1, r, erases,
			       programs, flash_errors);
		}
	}

	f = fopen(argv[2], "wb");
	fwrite(host_flash, 1, FLASH_SIZE, f);
	fclose(f);
	return 0;
}
