// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Every exception cause must make nandtier_core assert trap and halt.
// Build with -DCASE=<n>, one image per case. If the faulting instruction
// does not trap, the program reaches the TOHOST write below and the
// testbench reports a failure. Misaligned stores target TOHOST, so they
// must not even reach the bus.

	.equ TOHOST, 0x10000000

	.section .text.start
	.globl _start
_start:
	li t0, TOHOST
	la t1, scratch
	li a0, 1
	nop

#if CASE == 1		// all-zero word
	.word 0x00000000
#elif CASE == 2
	ecall
#elif CASE == 3
	ebreak
#elif CASE == 4		// misaligned word load
	lw a1, 2(t1)
#elif CASE == 5		// misaligned halfword load
	lhu a1, 1(t1)
#elif CASE == 6		// misaligned word store
	sw a0, 2(t0)
#elif CASE == 7		// misaligned halfword store
	sh a0, 3(t0)
#elif CASE == 8		// jalr to a target with bit 1 set
	la t2, _start
	jalr ra, 2(t2)
#elif CASE == 9		// beq x0, x0, .+2
	.word 0x00000163
#elif CASE == 10	// jal x0, .+2
	.word 0x0020006f
#elif CASE == 11	// write to a read-only counter
	csrw cycle, a0
#elif CASE == 12	// counters are read-only, even if the set mask is zero
	csrrs a1, instret, zero
	li a2, 0
	csrrs a1, instret, a2
#elif CASE == 13	// unsupported CSR
	csrr a1, mstatus
#elif CASE == 14	// mret (no machine-mode trap support)
	mret
#elif CASE == 15	// compressed instruction (C extension not supported)
	.half 0x0001	// c.nop
	.half 0x0001
#elif CASE == 16	// SUB encoding with funct3 = OR
	.word 0x40b56533
#else
#error "unknown CASE"
#endif

	sw a0, 0(t0)	// must never get here
1:	j 1b

	.data
	.align 4
scratch:
	.word 0
