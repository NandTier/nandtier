// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0

#include "nandtier.h"
#include "console.h"

void print_char(char c)
{
	if (c == '\n')
		UART_DATA = '\r';
	UART_DATA = (uint8_t)c;
}

void print(const char *s)
{
	while (*s)
		print_char(*s++);
}

void print_hex(uint32_t value, int digits)
{
	for (int shift = (digits - 1) * 4; shift >= 0; shift -= 4)
		print_char("0123456789abcdef"[(value >> shift) & 0xF]);
}

void print_dec(uint32_t value)
{
	char buf[10];
	int n = 0;
	do {
		buf[n++] = '0' + value % 10;
		value /= 10;
	} while (value);
	while (n)
		print_char(buf[--n]);
}

char get_char(void)
{
	uint32_t v;
	while ((v = UART_DATA) == 0xFFFFFFFFu)
		;
	return (char)v;
}

void wait_ms(uint32_t ms)
{
	while (ms--) {
		uint32_t start = nt_cycles();
		while (nt_cycles() - start < NT_CLK_HZ / 1000)
			;
	}
}
