/*
 * Copyright 2026 Abdul Muheet Ghani
 * SPDX-License-Identifier: Apache-2.0
 *
 * Game cartridge layout: code and constants run from the cartridge slot of
 * the SPI flash (NT_CART_SLOT, where the launcher copies the game from the
 * SD card), data, bss and the stack live in the 8 KiB SRAM. The last 16
 * bytes of the SRAM are the handoff message (nt_handoff in nandtier.h).
 */

OUTPUT_ARCH(riscv)
ENTRY(_start)

MEMORY
{
	FLASH (rx)  : ORIGIN = 0x00100000, LENGTH = 1M
	RAM   (rwx) : ORIGIN = 0x40000000, LENGTH = 8K
}

SECTIONS
{
	.text : {
		KEEP(*(.text.start))
		*(.text .text.*)
	} > FLASH

	.rodata : {
		*(.rodata .rodata.* .srodata .srodata.*)
		. = ALIGN(4);
	} > FLASH

	.data : {
		__data_start = .;
		*(.data .data.*)
		__global_pointer$ = . + 0x800;
		*(.sdata .sdata.*)
		. = ALIGN(4);
		__data_end = .;
	} > RAM AT > FLASH
	__data_load = LOADADDR(.data);

	.bss (NOLOAD) : {
		. = ALIGN(4);
		__bss_start = .;
		*(.sbss .sbss.* .bss .bss.* COMMON)
		. = ALIGN(4);
		__bss_end = .;
	} > RAM

	__stack_top = ORIGIN(RAM) + LENGTH(RAM) - 16;
	ASSERT(__bss_end + 1024 <= __stack_top, "less than 1 KiB of SRAM left for the stack")
	/* the launcher jumps to the start of the slot; a game function named
	   start() would land in .text.start too (-ffunction-sections) */
	ASSERT(_start == ORIGIN(FLASH), "_start is not first in the cartridge: rename the game's start() function")
}
