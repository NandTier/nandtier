// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Running as a game cartridge: started by the launcher (fw/fw-flash) from
// the cartridge slot of the SPI flash.

#ifndef CART_H
#define CART_H

#include <stdint.h>

void cart_print(const char *s);         // on the UART, '\n' as "\r\n"
void cart_print_dec(uint32_t v);

// Back to the launcher's game menu. Prints the frame time line
// ("Game over. Slowest frame: N of 419580 cycles") first.
void cart_exit(uint32_t slowest_frame) __attribute__((noreturn));

#endif
