// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// For fw/fw-flash/loader.c built on a PC (LOADER_HOST): the SPI flash and
// the SD card are models in loader_host.c.

#ifndef LOADER_HOST_H
#define LOADER_HOST_H

#include <stdint.h>

extern uint8_t  host_flash[];
extern uint32_t host_xip_offset;        // the board's FLASH_OFFSET
#define XIP_MEMORY (host_flash + host_xip_offset)

void host_flash_io(uint8_t *buf, int len, int wren);
#undef nt_flash_io
#define nt_flash_io host_flash_io

#endif
