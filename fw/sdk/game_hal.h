// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// What a game needs from the machine. On the board these are register
// accesses; built with GAME_HOST (test/host/) they go to a software model
// of the PPU, so the games can run and be checked on a PC.

#ifndef GAME_HAL_H
#define GAME_HAL_H

#include <stdint.h>
#include "nandtier.h"

#ifdef GAME_HOST

void     hal_ppu_write(uint32_t offset, uint32_t value);
uint32_t hal_ppu_read(uint32_t offset);
int      hal_key(void);                 // next byte from the keyboard link, -1 if none
void     hal_uart_put(uint8_t b);       // a byte to the PC
uint32_t hal_frame_count(void);         // the PPU's frame counter (no side effects)
static inline uint32_t hal_cycles(void) { return 0; }

#else

static inline uint32_t hal_cycles(void)
{
	return nt_cycles();
}

static inline void hal_ppu_write(uint32_t offset, uint32_t value)
{
	PPU_REG(offset) = value;
}

static inline uint32_t hal_ppu_read(uint32_t offset)
{
	return PPU_REG(offset);
}

static inline uint32_t hal_frame_count(void)
{
	return PPU_REG(PPU_STATUS) >> 16;
}

static inline int hal_key(void)
{
	uint32_t v = UART_DATA;
	return v == 0xFFFFFFFFu ? -1 : (int)(v & 0xFF);
}

// Waits while the previous byte is still going out (about 2170 cycles a
// byte at 115200 baud).
static inline void hal_uart_put(uint8_t b)
{
	UART_DATA = b;
}

#endif

#endif
