// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Text console on the UART (everything also appears on the HDMI terminal).

#ifndef CONSOLE_H
#define CONSOLE_H

#include <stdint.h>

void print_char(char c);                // '\n' is sent as "\r\n"
void print(const char *s);
void print_hex(uint32_t value, int digits);
void print_dec(uint32_t value);
char get_char(void);                    // waits for a key
void wait_ms(uint32_t ms);

#endif
