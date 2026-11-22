// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// SD card access in SPI mode (SD Physical Layer Simplified Specification,
// chapter 7) through the NandTier SD SPI port.

#include "nandtier.h"
#include "sd.h"

#define DIV_INIT    32      // SCK about 390 kHz: the card must start below 400 kHz
#define DIV_FAST    6       // SCK about 2 MHz

static uint8_t xfer(uint8_t out)
{
	SD_TX = out;
	while (SD_CTRL & SD_CTRL_BUSY)
		;
	return SD_RX;
}

static void select_card(int on)
{
	// MOSI idles high, SCK low
	SD_CTRL = SD_CTRL_MOSI | (on ? 0 : SD_CTRL_CS);
}

static void deselect(void)
{
	select_card(0);
	xfer(0xFF);         // the card releases MISO after one more byte
}

static void wait_cycles(uint32_t n)
{
	uint32_t start = nt_cycles();
	while (nt_cycles() - start < n)
		;
}

// Send a command, return the R1 answer (bit 7 set: no answer). The card
// stays selected.
static uint8_t command(uint8_t cmd, uint32_t arg, uint8_t crc)
{
	uint8_t r1 = 0xFF;

	select_card(1);
	for (int i = 0; i < 1000 && xfer(0xFF) != 0xFF; i++)
		;
	xfer(0x40 | cmd);
	xfer(arg >> 24);
	xfer(arg >> 16);
	xfer(arg >> 8);
	xfer(arg);
	xfer(crc);
	for (int i = 0; i < 10 && (r1 & 0x80); i++)
		r1 = xfer(0xFF);
	return r1;
}

int sd_init(uint8_t r7[2])
{
	uint8_t r1;
	int status = 0;

	SD_DIV = DIV_INIT;
	select_card(0);
	wait_cycles(NT_CLK_HZ / 1000);          // 1 ms after power-up
	for (int i = 0; i < 10; i++)            // at least 74 clocks with CS high
		xfer(0xFF);

	r1 = command(0, 0, 0x95);
	if (r1 != 0x01) {
		status = 0x10 | (r1 & 0x0F);
		goto done;
	}

	r1 = command(8, 0x1AA, 0x87);
	if (r1 != 0x01) {
		status = 0x20 | (r1 & 0x0F);
		goto done;
	}
	xfer(0xFF);
	xfer(0xFF);
	r7[0] = xfer(0xFF);
	r7[1] = xfer(0xFF);
	if (r7[0] != 0x01 || r7[1] != 0xAA) {
		status = 0x30;
		goto done;
	}

	// ACMD41 with HCS until the card leaves the idle state (up to ~1 s)
	status = 0x05;
	for (int i = 0; i < 1000; i++) {
		r1 = command(55, 0, 0x01);
		if (r1 > 0x01) {
			status = 0x40 | (r1 & 0x0F);
			break;
		}
		r1 = command(41, 0x40000000, 0x01);
		if (r1 == 0x00) {
			status = 0;
			break;
		}
		deselect();
		wait_cycles(NT_CLK_HZ / 1000);
	}
	if (status)
		goto done;

	r1 = command(16, SD_BLOCK_SIZE, 0x01);
	if (r1 != 0x00)
		status = 0x60 | (r1 & 0x0F);

done:
	deselect();
	if (status == 0)
		SD_DIV = DIV_FAST;
	return status;
}

int sd_read_block(uint32_t block, uint8_t *buf)
{
	int ok = 0;

	if (command(17, block, 0x01) == 0x00) {
		for (uint32_t i = 0; i < 100000; i++) {
			uint8_t token = xfer(0xFF);
			if (token == 0xFE) {
				for (int j = 0; j < SD_BLOCK_SIZE; j++)
					buf[j] = xfer(0xFF);
				xfer(0xFF);         // CRC, ignored
				xfer(0xFF);
				ok = 1;
				break;
			}
			if (token != 0xFF)      // error token
				break;
		}
	}
	deselect();
	return ok ? 0 : -1;
}

int sd_write_block(uint32_t block, const uint8_t *buf)
{
	int ok = 0;

	if (command(24, block, 0x01) == 0x00) {
		xfer(0xFF);
		xfer(0xFE);                 // start token
		for (int j = 0; j < SD_BLOCK_SIZE; j++)
			xfer(buf[j]);
		xfer(0xFF);                 // dummy CRC
		xfer(0xFF);
		if ((xfer(0xFF) & 0x1F) == 0x05) {
			// accepted: MISO stays low while the card programs
			for (uint32_t i = 0; i < 1000000; i++) {
				if (xfer(0xFF) != 0x00) {
					ok = 1;
					break;
				}
			}
		}
	}
	deselect();
	return ok ? 0 : -1;
}
