/*
 * Copyright 2026 Abdul Muheet Ghani
 * SPDX-License-Identifier: Apache-2.0
 *
 * Memory layout for the core test programs: 64 KiB of RAM at 0x8000_0000.
 */

OUTPUT_ARCH("riscv")
ENTRY(_start)

MEMORY
{
	RAM (rwx) : ORIGIN = 0x80000000, LENGTH = 64K
}

SECTIONS
{
	.text : {
		*(.text.start)
		*(.text*)
	} > RAM

	.rodata : { *(.rodata*) *(.srodata*) } > RAM

	.data : {
		__global_pointer$ = . + 0x800;
		*(.data*) *(.sdata*)
	} > RAM

	.bss (NOLOAD) : {
		_bss_start = .;
		*(.bss*) *(.sbss*) *(COMMON)
		. = ALIGN(4);
		_bss_end = .;
	} > RAM

	_stack_top = ORIGIN(RAM) + LENGTH(RAM);
}
