// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Self-checking RV32I instruction test for nandtier_core.
// gp holds the number of the test being run; on a mismatch the
// testbench reports it as "test #N failed".

	.equ TOHOST, 0x10000000

	.macro TEST n
	li gp, \n
	.endm

	.macro CHECK reg, expected
	li t6, \expected
	bne \reg, t6, fail
	.endm

	.section .text.start
	.globl _start
_start:
	li sp, 0x80010000

	// --- register/immediate ALU -----------------------------------------
	TEST 1
	li a0, 5
	li a1, 7
	add a2, a0, a1
	CHECK a2, 12
	sub a2, a0, a1
	CHECK a2, -2
	addi a2, a0, -10
	CHECK a2, -5

	TEST 2
	li a0, 0xF0F0F0F0
	li a1, 0x0FF00FF0
	and a2, a0, a1
	CHECK a2, 0x00F000F0
	or a2, a0, a1
	CHECK a2, 0xFFF0FFF0
	xor a2, a0, a1
	CHECK a2, 0xFF00FF00
	andi a2, a0, 0x0FF
	CHECK a2, 0xF0
	ori a2, a0, 0x00F
	CHECK a2, 0xF0F0F0FF
	xori a2, a0, -1
	CHECK a2, 0x0F0F0F0F

	TEST 3
	li a0, 0x80000001
	slli a2, a0, 4
	CHECK a2, 0x00000010
	srli a2, a0, 4
	CHECK a2, 0x08000000
	srai a2, a0, 4
	CHECK a2, 0xF8000000
	li a1, 31
	sll a2, a0, a1
	CHECK a2, 0x80000000
	srl a2, a0, a1
	CHECK a2, 1
	sra a2, a0, a1
	CHECK a2, -1

	TEST 4
	li a0, -1
	li a1, 1
	slt a2, a0, a1
	CHECK a2, 1
	sltu a2, a0, a1
	CHECK a2, 0
	slti a2, a0, 0
	CHECK a2, 1
	sltiu a2, a1, -1
	CHECK a2, 1

	TEST 5
	lui a0, 0x12345
	CHECK a0, 0x12345000
1:	auipc a1, 0
	la a2, 1b
	bne a1, a2, fail

	// --- loads and stores ------------------------------------------------
	TEST 6
	la a0, scratch
	li a1, 0x8899AABB
	sw a1, 0(a0)
	lw a2, 0(a0)
	CHECK a2, 0x8899AABB
	lb a2, 0(a0)
	CHECK a2, 0xFFFFFFBB
	lbu a2, 0(a0)
	CHECK a2, 0xBB
	lh a2, 2(a0)
	CHECK a2, 0xFFFF8899
	lhu a2, 2(a0)
	CHECK a2, 0x8899

	TEST 7
	li a1, 0x11
	sb a1, 1(a0)
	lw a2, 0(a0)
	CHECK a2, 0x889911BB
	li a1, 0x2233
	sh a1, 2(a0)
	lw a2, 0(a0)
	CHECK a2, 0x223311BB

	// --- branches and jumps ----------------------------------------------
	TEST 8
	li a0, -3
	li a1, 4
	beq a0, a1, fail
	bne a0, a0, fail
	bge a0, a1, fail
	blt a1, a0, fail
	bltu a0, a1, fail
	bgeu a1, a0, fail
	blt a0, a1, 1f
	j fail
1:	bltu a1, a0, 2f
	j fail
2:	bge a1, a0, 3f
	j fail
3:	bgeu a0, a1, 4f
	j fail
4:

	TEST 9
	jal ra, func
	CHECK a0, 42
	la t0, func
	jalr ra, 0(t0)
	CHECK a0, 42

	// --- loop: sum 1..100 --------------------------------------------------
	TEST 10
	li a0, 0
	li a1, 100
1:	add a0, a0, a1
	addi a1, a1, -1
	bnez a1, 1b
	CHECK a0, 5050

	// --- x0 stays zero -----------------------------------------------------
	TEST 11
	li x0, 123
	bnez x0, fail

	// --- cycle / instret counters (ENABLE_COUNTERS=1) ----------------------
	TEST 12
	rdcycle a0
	nop
	nop
	rdcycle a1
	bgeu a0, a1, fail
	rdinstret a0
	rdinstret a1
	bgeu a0, a1, fail

	// --- exact instret, the other counter read forms -----------------------
	TEST 13
	rdinstret a0
	nop
	nop
	rdinstret a1
	sub a2, a1, a0
	CHECK a2, 3
	rdcycleh a0
	CHECK a0, 0
	rdinstreth a0
	CHECK a0, 0
	rdtimeh a0
	CHECK a0, 0
	rdtime a0
	rdcycle a1
	bgeu a0, a1, fail
	csrrc a0, instret, zero
	csrrsi a1, instret, 0
	csrrci a2, instret, 0
	bgeu a0, a1, fail
	bgeu a1, a2, fail

	// --- FENCE and FENCE.I are no-ops --------------------------------------
	TEST 14
	li a0, 7
	fence
	fence.i
	fence rw, rw
	CHECK a0, 7

	// --- JALR clears bit 0 of the target, rd may equal rs1 -----------------
	TEST 15
	la t0, func
	jalr ra, 1(t0)
	CHECK a0, 42
	li a0, 0
	la ra, func
	jalr ra, 0(ra)
	CHECK a0, 42

	// --- loads into x0 and into their own base register --------------------
	TEST 16
	la a0, scratch
	li a1, 0x12345678
	sw a1, 0(a0)
	lw x0, 0(a0)
	bnez x0, fail
	addi a0, a0, 4
	lw a0, -4(a0)
	CHECK a0, 0x12345678
	add a0, a0, a0
	CHECK a0, 0x2468ACF0

pass:
	li a0, 1
	li t0, TOHOST
	sw a0, 0(t0)
1:	j 1b

fail:
	slli a0, gp, 1
	ori a0, a0, 1
	li t0, TOHOST
	sw a0, 0(t0)
1:	j 1b

func:
	li a0, 42
	ret

	.data
	.align 4
scratch:
	.word 0
