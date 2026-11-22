// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier boot ROM: after reset, listen on the UART for half a second.
// If the programmer (sw/nandtier-programmer.py) sends 0x55, answer 0x56 and
// serve its commands; otherwise start the user firmware in flash.
//
//   host sends                          reply
//   55                                  56                ping
//   10 n d0..dn                         11, sum(d)        fill the page buffer (n+1 bytes)
//   30 a2 a1 a0                         31 ... 32         erase the 4 KiB sector at a
//   40 a2 a1 a0                         41 ... 42         program the page buffer at a
//   60                                  61, status [r7]   initialise the SD card (see sd.h)
//   62 b3 b2 b1 b0 d0..d511 sum         63, result        write SD block b: 0 ok, 1 failed,
//                                                         2 checksum wrong
//   F0                                  F1                restart the boot ROM

#include "nandtier.h"
#include "sd.h"

#define ISP_WAIT_CYCLES (NT_CLK_HZ / 2)
#define SD_BUFFER       ((uint8_t *)NT_SRAM_BASE)

#define FLASH_WREN      0x06
#define FLASH_RDSR      0x05
#define FLASH_SE        0x20
#define FLASH_PP        0x02

void flash_io(uint8_t *buf, int len, int wren);

// --- UART ------------------------------------------------------------------------

static uint8_t uart_get(void)
{
	uint32_t v;
	while ((v = UART_DATA) == 0xFFFFFFFFu)
		;
	return v;
}

static void uart_put(uint8_t b)
{
	UART_DATA = b;
}

// --- flash, bit-banged -------------------------------------------------------------
//
// Called by the user firmware too (through the jump at 0x8000_0054), so
// everything here must stay in boot RAM and must not rely on gp.

static uint8_t spi_byte(uint8_t out)
{
	uint8_t in = 0;
	for (int bit = 7; bit >= 0; bit--) {
		uint8_t mosi = (out >> bit) & 1 ? FLASH_PIN_IO0 : 0;
		FLASHCFG_PINS = mosi;                       // CS low, SCK low, data out
		FLASHCFG_PINS = mosi | FLASH_PIN_CLK;       // rising edge
		in = (in << 1) | ((FLASHCFG_PINS & FLASH_PIN_IO1) ? 1 : 0);
	}
	FLASHCFG_PINS = 0;
	return in;
}

static void spi_end(void)
{
	FLASHCFG_PINS = FLASH_PIN_CSB;
}

void flash_io(uint8_t *buf, int len, int wren)
{
	FLASHCFG_EN   = 0;                  // XIP off; returns once the pins are ours
	FLASHCFG_PINS = FLASH_PIN_CSB;
	FLASHCFG_OE   = FLASH_OE_IO0;

	if (wren) {
		spi_byte(FLASH_WREN);
		spi_end();
	}

	for (int i = 0; i < len; i++)
		buf[i] = spi_byte(buf[i]);
	spi_end();

	if (wren) {
		uint8_t status;
		do {
			spi_byte(FLASH_RDSR);
			status = spi_byte(0);
			spi_end();
		} while (status & 0x01);    // write in progress
	}

	FLASHCFG_OE = 0;
	FLASHCFG_EN = FLASH_EN_XIP;     // XIP on: the flash is woken up again
}

// --- command loop -----------------------------------------------------------------

static uint32_t get_addr24(void)
{
	uint32_t a = uart_get();
	a = (a << 8) | uart_get();
	return (a << 8) | uart_get();
}

static void __attribute__((noreturn)) serve(void)
{
	// one buffer for "command, 3 address bytes, page data"
	static uint8_t cmd[4 + 256];
	int page_len = 0;

	for (;;) {
		switch (uart_get()) {
		case 0x55:
			uart_put(0x56);
			break;

		case 0x10: {
			uint8_t sum = 0;
			uart_put(0x11);
			page_len = uart_get() + 1;
			for (int i = 0; i < page_len; i++) {
				cmd[4 + i] = uart_get();
				sum += cmd[4 + i];
			}
			uart_put(sum);
			break;
		}

		case 0x30: {                    // erase the sector
			uint32_t a;
			uart_put(0x31);
			a = get_addr24();
			cmd[0] = FLASH_SE;
			cmd[1] = a >> 16;
			cmd[2] = a >> 8;
			cmd[3] = a;
			flash_io(cmd, 4, 1);
			uart_put(0x32);
			break;
		}

		case 0x40: {                    // program the page buffer
			uint32_t a;
			uart_put(0x41);
			a = get_addr24();
			cmd[0] = FLASH_PP;
			cmd[1] = a >> 16;
			cmd[2] = a >> 8;
			cmd[3] = a;
			if (page_len)
				flash_io(cmd, 4 + page_len, 1);
			page_len = 0;           // flash_io() overwrote the data
			uart_put(0x42);
			break;
		}

		case 0x60: {
			uint8_t r7[2] = {0, 0};
			uart_put(0x61);
			int status = sd_init(r7);
			uart_put(status);
			if (status == 0x30) {
				uart_put(r7[0]);
				uart_put(r7[1]);
			}
			break;
		}

		case 0x62: {
			uint32_t block = 0;
			uint8_t sum = 0;
			uart_put(0x63);
			for (int i = 0; i < 4; i++)
				block = (block << 8) | uart_get();
			for (int i = 0; i < SD_BLOCK_SIZE; i++) {
				SD_BUFFER[i] = uart_get();
				sum += SD_BUFFER[i];
			}
			if (uart_get() != sum)
				uart_put(2);
			else
				uart_put(sd_write_block(block, SD_BUFFER) == 0 ? 0 : 1);
			break;
		}

		case 0xF0:
			uart_put(0xF1);
			((void (*)(void))NT_BOOT_BASE)();
			break;

		default:
			break;
		}
	}
}

int main(void)
{
	UART_DIV = (NT_CLK_HZ + NT_UART_BAUD / 2) / NT_UART_BAUD;

	uint32_t start = nt_cycles();
	while (nt_cycles() - start < ISP_WAIT_CYCLES) {
		if (UART_DATA == 0x55) {
			uart_put(0x56);
			serve();
		}
	}

	((void (*)(void))NT_FLASH_BASE)();
	return 0;
}
