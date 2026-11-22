// Copyright 2024-2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier user firmware ("the launcher"): a menu on the UART / HDMI
// terminal for the LEDs, the SPI flash read modes, a CPU benchmark, the SD
// card and tic-tac-toe, and the game menu, which starts the game
// cartridges from the SD card (arcade.c, loader.c).

#include <stdint.h>
#include "nandtier.h"
#include "console.h"
#include "sd.h"
#include "tictactoe.h"
#include "arcade.h"
#include "loader.h"

#define LED_MASK        0x3F            // GPIO 0..5 drive LEDs 1..6
#define SD_TEST_BLOCK   1024

static uint8_t sd_buffer[SD_BLOCK_SIZE];

// --- SPI flash ---------------------------------------------------------------------

static void flash_set_mode(uint8_t mode)
{
	// the controller re-initialises the flash; the next instruction fetch waits
	FLASHCFG_MODE = mode;
}

static void flash_show_mode(void)
{
	uint8_t mode = FLASHCFG_MODE;
	print("Flash reads: ");
	print(mode & FLASH_MODE_DUAL ? "dual I/O" : "single");
	print(mode & FLASH_MODE_CRM ? ", continuous read mode\n" : "\n");
}

static void flash_show_id(void)
{
	uint8_t buf[4] = {0x9F, 0, 0, 0};       // JEDEC ID
	nt_flash_io(buf, 4, 0);
	print("Flash JEDEC ID:");
	for (int i = 1; i < 4; i++) {
		print(" ");
		print_hex(buf[i], 2);
	}
	print("\nFirmware at flash address 0x");
	print_hex(loader_flash_base(), 6);
	print("\n");
}

// --- benchmark -------------------------------------------------------------------

static uint8_t sieve[2048];

// Primes below 2048 (sieve of Eratosthenes), then a CRC-32 of the sieve.
static uint32_t bench_work(void)
{
	uint32_t primes = 0, crc = 0xFFFFFFFF;

	for (int i = 0; i < 2048; i++)
		sieve[i] = i >= 2;
	for (int i = 2; i * i < 2048; i++)
		if (sieve[i])
			for (int j = i * i; j < 2048; j += i)
				sieve[j] = 0;
	for (int i = 0; i < 2048; i++) {
		primes += sieve[i];
		crc ^= sieve[i];
		for (int b = 0; b < 8; b++)
			crc = (crc >> 1) ^ (0xEDB88320 & -(crc & 1));
	}
	return ~crc ^ primes;
}

static uint32_t benchmark(int verbose)
{
	uint32_t c0 = nt_cycles(), i0 = nt_instret();
	uint32_t result = bench_work();
	uint32_t cycles = nt_cycles() - c0, instr = nt_instret() - i0;

	if (verbose) {
		print("Cycles:       "); print_dec(cycles); print("\n");
		print("Instructions: "); print_dec(instr); print("\n");
		print("Cycles/instr: "); print_dec(cycles / instr); print(".");
		print_dec(cycles * 10 / instr % 10); print("\n");
		print("Result:       "); print_hex(result, 8);
		print(result == 0x434eb1e3 ? " (ok)\n" : " (WRONG)\n");
	}
	return cycles;
}

static void benchmark_all(void)
{
	static const struct { const char *name; uint8_t mode; } modes[] = {
		{"single         ", 0},
		{"dual I/O       ", FLASH_MODE_DUAL},
		{"dual I/O + CRM ", FLASH_MODE_DUAL | FLASH_MODE_CRM},
	};
	uint8_t old = FLASHCFG_MODE;

	for (unsigned i = 0; i < sizeof(modes) / sizeof(modes[0]); i++) {
		flash_set_mode(modes[i].mode);
		uint32_t cycles = benchmark(0);
		print(modes[i].name);
		print(": ");
		print_dec(cycles);
		print(" cycles\n");
	}
	flash_set_mode(old);
}

// --- SD card ------------------------------------------------------------------------

static int sd_start(void)
{
	uint8_t r7[2];
	int status = sd_init(r7);
	if (status) {
		print("SD init failed, status 0x");
		print_hex(status, 2);
		print("\n");
	}
	return status;
}

static void sd_read_test(void)
{
	if (sd_start())
		return;
	if (sd_read_block(SD_TEST_BLOCK, sd_buffer)) {
		print("SD read failed\n");
		return;
	}
	print("SD block ");
	print_dec(SD_TEST_BLOCK);
	print(":");
	for (int i = 0; i < 16; i++) {
		print(" ");
		print_hex(sd_buffer[i], 2);
	}
	print(" ...\n");
}

static void sd_write_test(void)
{
	if (sd_start())
		return;
	for (int i = 0; i < SD_BLOCK_SIZE; i++)
		sd_buffer[i] = i ^ 0xA5;
	if (sd_write_block(SD_TEST_BLOCK, sd_buffer)) {
		print("SD write failed\n");
		return;
	}
	for (int i = 0; i < SD_BLOCK_SIZE; i++)
		sd_buffer[i] = 0;
	if (sd_read_block(SD_TEST_BLOCK, sd_buffer)) {
		print("SD read back failed\n");
		return;
	}
	for (int i = 0; i < SD_BLOCK_SIZE; i++) {
		if (sd_buffer[i] != (uint8_t)(i ^ 0xA5)) {
			print("SD verify failed at byte ");
			print_dec(i);
			print("\n");
			return;
		}
	}
	print("SD write and verify OK (block ");
	print_dec(SD_TEST_BLOCK);
	print(")\n");
}

// --- menu -------------------------------------------------------------------------

static void show_menu(void)
{
	print("\nNandTier - select an action:\n\n");
	print("  [1]-[6] toggle LED 1-6\n");
	print("  [F] show the flash read mode     [I] read the flash ID\n");
	print("  [S] single flash reads           [D] dual I/O reads\n");
	print("  [C] dual I/O + continuous read mode\n");
	print("  [B] run the benchmark            [A] benchmark every flash mode\n");
	print("  [G] tic-tac-toe\n");
	print("  [T] initialise the SD card       [R] read an SD test block\n");
	print("  [W] write and verify an SD test block\n");
	print("  [P] game menu: play the games on the SD card (HDMI screen)\n");
	print("  [M] about\n");
}

int main(void)
{
	UART_DIV = (NT_CLK_HZ + NT_UART_BAUD / 2) / NT_UART_BAUD;

	// LED chaser to show the firmware is alive (not on the way back from a game)
	GPIO_OE  = LED_MASK;
	GPIO_OUT = LED_MASK;                    // LEDs are active low
	for (int i = 0; i < 6 && nt_handoff_cmd() != NT_HANDOFF_RETURN; i++) {
		GPIO_OUT = LED_MASK ^ (1 << i);
		wait_ms(60);
	}
	GPIO_OUT = LED_MASK;

	flash_set_mode(FLASH_MODE_DUAL | FLASH_MODE_CRM);

	// back from a game: straight to the game menu, on that game
	if (nt_handoff_cmd() == NT_HANDOFF_RETURN) {
		int sel = NT_HANDOFF->arg;
		NT_HANDOFF->magic = 0;
		arcade(sel);
	}
	NT_HANDOFF->magic = 0;

	for (;;) {
		show_menu();
		print("\n> ");
		char key = get_char();
		if (key > ' ' && key < 127)
			print_char(key);
		print("\n");

		switch (key) {
		case '1': case '2': case '3': case '4': case '5': case '6':
			GPIO_OUT ^= 1 << (key - '1');
			break;
		case 'F': case 'f': flash_show_mode(); break;
		case 'I': case 'i': flash_show_id(); break;
		case 'S': case 's': flash_set_mode(0); flash_show_mode(); break;
		case 'D': case 'd': flash_set_mode(FLASH_MODE_DUAL); flash_show_mode(); break;
		case 'C': case 'c': flash_set_mode(FLASH_MODE_DUAL | FLASH_MODE_CRM); flash_show_mode(); break;
		case 'B': case 'b': benchmark(1); break;
		case 'A': case 'a': benchmark_all(); break;
		case 'G': case 'g': tictactoe(); break;
		case 'T': case 't':
			if (sd_start() == 0)
				print("SD card initialised.\n");
			break;
		case 'R': case 'r': sd_read_test(); break;
		case 'W': case 'w': sd_write_test(); break;
		case 'P': case 'p': arcade(0); break;
		case 'M': case 'm': print("NandTier by Abdul Muheet Ghani\n"); break;
		default: break;
		}
	}
}
