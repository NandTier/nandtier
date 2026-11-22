/*
 * Copyright 2026 Abdul Muheet Ghani
 * SPDX-License-Identifier: Apache-2.0
 *
 * Boot ROM layout: everything, including the stack, lives in the 8 KiB
 * boot RAM. The image has no writable initialised data, because a reset
 * through the ISP "0xF0" command does not reload it.
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
	BOOT (rwx) : ORIGIN = 0x80000000, LENGTH = 8K
}

SECTIONS
{
	.text : {
		KEEP(*(.text.start))
		*(.text .text.*)
	} > BOOT

	.rodata : {
		*(.rodata .rodata.* .srodata .srodata.*)
	} > BOOT

	.data : {
		*(.data .data.* .sdata .sdata.*)
	} > BOOT

	ASSERT(SIZEOF(.data) == 0, "boot ROM must not have initialised writable data")

	.bss (NOLOAD) : {
		. = ALIGN(4);
		__bss_start = .;
		*(.bss .bss.* .sbss .sbss.* COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} > BOOT

	__stack_top = ORIGIN(BOOT) + LENGTH(BOOT);
}
