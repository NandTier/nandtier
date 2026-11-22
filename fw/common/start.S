// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Program entry for code that runs from the SPI flash: the user firmware
// at 0x0000_0000 (where the boot ROM jumps) and the game cartridges at
// 0x0010_0000 (where the launcher jumps). Sets up sp and gp, copies .data
// from flash to SRAM, clears .bss and calls main().

	.section .text.start, "ax"
	.globl _start
_start:
	la sp, __stack_top
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop

	la t0, __data_load
	la t1, __data_start
	la t2, __data_end
1:	bgeu t1, t2, 2f
	lw t3, 0(t0)
	sw t3, 0(t1)
	addi t0, t0, 4
	addi t1, t1, 4
	j 1b
2:
	la t0, __bss_start
	la t1, __bss_end
3:	bgeu t0, t1, 4f
	sw zero, 0(t0)
	addi t0, t0, 4
	j 3b
4:
	call main
5:	j 5b
