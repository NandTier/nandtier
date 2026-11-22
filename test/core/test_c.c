// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// C program test for nandtier_core (rv32i, no hardware mul/div,
// so multiply/divide go through libgcc). Returns 0 on success or
// the number of the first failing check.

#include <stdint.h>

#define CONSOLE (*(volatile uint32_t *)0x10000004)

static void putstr(const char *s)
{
	while (*s)
		CONSOLE = *s++;
}

static void puthex(uint32_t v)
{
	for (int i = 28; i >= 0; i -= 4)
		CONSOLE = "0123456789abcdef"[(v >> i) & 0xf];
}

static uint32_t fib(uint32_t n)
{
	return n < 2 ? n : fib(n - 1) + fib(n - 2);
}

static uint32_t crc32(const uint8_t *data, int len)
{
	uint32_t crc = 0xffffffff;
	for (int i = 0; i < len; i++) {
		crc ^= data[i];
		for (int b = 0; b < 8; b++)
			crc = (crc >> 1) ^ (0xedb88320 & -(crc & 1));
	}
	return ~crc;
}

static void sort(int32_t *a, int n)
{
	for (int i = 0; i < n - 1; i++)
		for (int j = 0; j < n - 1 - i; j++)
			if (a[j] > a[j + 1]) {
				int32_t t = a[j];
				a[j] = a[j + 1];
				a[j + 1] = t;
			}
}

static int32_t values[] = { 42, -7, 1000, 0, -300, 17, 5, 99 };
static uint32_t zeroed[16];

int main(void)
{
	putstr("NandTier core C test\n");

	for (int i = 0; i < 16; i++)
		if (zeroed[i] != 0)
			return 1;

	if (fib(15) != 610)
		return 2;

	volatile uint32_t a = 123456, b = 789;
	if (a * b != 97406784u)
		return 3;
	if (a / b != 156 || a % b != 372)
		return 4;
	volatile int32_t c = -1000;
	if (c / 7 != -142 || c % 7 != -6)
		return 5;

	uint32_t crc = crc32((const uint8_t *)"123456789", 9);
	putstr("crc32 = 0x");
	puthex(crc);
	putstr("\n");
	if (crc != 0xcbf43926)
		return 6;

	sort(values, 8);
	for (int i = 0; i < 7; i++)
		if (values[i] > values[i + 1])
			return 7;
	if (values[0] != -300 || values[7] != 1000)
		return 8;

	putstr("all checks passed\n");
	return 0;
}
