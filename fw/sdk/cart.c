// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0

#include "nandtier.h"
#include "cart.h"

void cart_print(const char *s)
{
	for (; *s; s++) {
		if (*s == '\n')
			UART_DATA = '\r';
		UART_DATA = (uint8_t)*s;
	}
}

void cart_print_dec(uint32_t v)
{
	char buf[11];
	int n = 10;
	buf[n] = 0;
	do {
		buf[--n] = '0' + v % 10;
		v /= 10;
	} while (v);
	cart_print(&buf[n]);
}

void cart_exit(uint32_t slowest_frame)
{
	PPU_REG(PPU_CTRL) = PPU_CTRL_TERM;
	cart_print("\nGame over. Slowest frame: ");
	cart_print_dec(slowest_frame);
	cart_print(" of 419580 cycles\n");

	// the launcher starts again and opens its game menu on this game
	nt_handoff_set(NT_HANDOFF_RETURN, NT_HANDOFF->arg);
	((void (*)(void))NT_FLASH_BASE)();
	__builtin_unreachable();
}
