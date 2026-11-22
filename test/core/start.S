// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Minimal C runtime for the core tests: set up sp/gp, clear .bss,
// call main() and report its return value (0 = PASS) to TOHOST.

	.equ TOHOST, 0x10000000

	.section .text.start
	.globl _start
_start:
	la sp, _stack_top
	.option push
	.option norelax
	la gp, __global_pointer$
	.option pop

	la t0, _bss_start
	la t1, _bss_end
1:	bgeu t0, t1, 2f
	sw zero, 0(t0)
	addi t0, t0, 4
	j 1b
2:
	call main

	// main returned a0: 0 -> write 1 (PASS), N -> write (N<<1)|1 (FAIL #N)
	beqz a0, 3f
	slli a0, a0, 1
	ori a0, a0, 1
	j 4f
3:	li a0, 1
4:	li t0, TOHOST
	sw a0, 0(t0)
5:	j 5b
