// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Boot ROM entry, at the CPU reset vector 0x8000_0000.
//
// 0x8000_0054 holds a jump to flash_io(): the user firmware calls it there
// (NT_BOOT_FLASH_IO in nandtier.h) to talk to the flash while XIP is off,
// so that address must not move.
//
// The boot ROM is built without gp-relative addressing (see Makefile),
// because flash_io() also runs with the firmware's gp.

	.section .text.start, "ax"
	.globl _start
_start:
	j reset

	.org 0x54
	.globl flash_io_entry
flash_io_entry:
	j flash_io

reset:
	la sp, __stack_top

	la t0, __bss_start
	la t1, __bss_end
1:	bgeu t0, t1, 2f
	sw zero, 0(t0)
	addi t0, t0, 4
	j 1b
2:
	call main
3:	j 3b
