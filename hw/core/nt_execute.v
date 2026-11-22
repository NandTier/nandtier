// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier execute stage (purely combinational, works on the ID/EX
// stage register).
//
//   result   value written to rd by everything except loads
//   next_pc  PC of the next instruction (branch/jump target or pc + 4)
//   agu      base + imm: memory address for loads/stores, jump/branch
//            target, AUIPC result
//
// The jump and branch targets come from the address adder, so the ALU is
// only used by OP and OP-IMM instructions.

`timescale 1 ns / 1 ps

module nt_execute (
	input      [31:0] id_pc,
	input      [31:0] id_rs1,
	input      [31:0] id_rs2,
	input      [31:0] id_imm,
	input      [ 3:0] id_alu_op,
	input             id_alu_imm,
	input      [ 2:0] id_funct3,
	input             id_lui,
	input             id_auipc,
	input             id_jal,
	input             id_jalr,
	input             id_branch,
	input             id_load,
	input             id_store,
	input             id_csr,

	input      [31:0] csr_rdata,

	output     [31:0] result,
	output     [31:0] next_pc,
	output     [31:0] agu,
	output            jump_misaligned
);
	wire [31:0] alu_y;
	wire        branch_taken;

	nt_alu u_alu (
		.op(id_alu_op),
		.a (id_rs1),
		.b (id_alu_imm ? id_imm : id_rs2),
		.y (alu_y)
	);

	nt_branch u_branch (
		.funct3(id_funct3),
		.a     (id_rs1),
		.b     (id_rs2),
		.taken (branch_taken)
	);

	wire        rs1_based = id_jalr || id_load || id_store;
	wire [31:0] pc_plus4  = id_pc + 32'd4;

	assign agu = (rs1_based ? id_rs1 : id_pc) + id_imm;

	// JALR clears bit 0; for JAL and branches it is already 0
	wire [31:0] target = {agu[31:1], 1'b0};
	wire        taken  = id_jal || id_jalr || (id_branch && branch_taken);

	assign next_pc         = taken ? target : pc_plus4;
	assign jump_misaligned = taken && target[1];

	assign result = id_jal || id_jalr ? pc_plus4  :
	                id_lui            ? id_imm    :
	                id_auipc          ? agu       :
	                id_csr            ? csr_rdata :
	                                    alu_y;

endmodule

// ------------------------------------------------------------------------------------
// NandTier multiply / divide unit: the RISC-V M extension.
//
//   funct3  000 MUL  001 MULH  010 MULHSU  011 MULHU
//           100 DIV  101 DIVU  110 REM     111 REMU
//
// go is held while the instruction is in EXECUTE; done rises when y holds
// the result and stays until go falls. Multiplies take one cycle (a 33 x
// 33 signed product, which covers all four kinds; the FPGA's multiplier
// blocks), divides 34 cycles (restoring division of the magnitudes, one
// bit per cycle, signs fixed at the end). Division by zero gives all ones
// (and the dividend as the remainder); -2^31 / -1 gives -2^31, remainder 0,
// as the specification says.

module nt_muldiv (
	input             clk,
	input             resetn,
	input             go,
	input      [ 2:0] funct3,
	input      [31:0] a,
	input      [31:0] b,
	output reg        done,
	output reg [31:0] y
);
	// --- multiply ------------------------------------------------------------------

	wire a_signed = funct3[1:0] == 2'b01 || funct3[1:0] == 2'b10;   // MULH, MULHSU
	wire b_signed = funct3[1:0] == 2'b01;                           // MULH
	wire signed [32:0] ma = {a_signed & a[31], a};
	wire signed [32:0] mb = {b_signed & b[31], b};
	wire signed [65:0] prod = ma * mb;

	// --- divide ------------------------------------------------------------------------

	wire is_div   = funct3[2];
	wire signed_d = !funct3[0];                 // DIV, REM
	wire want_rem = funct3[1];                  // REM, REMU

	reg  [31:0] quot, rem, divisor;
	reg  [ 5:0] count;
	reg         running, neg_q, neg_r;

	wire [32:0] rem_sh = {rem, quot[31]};
	wire [32:0] diff   = rem_sh - {1'b0, divisor};
	wire        fits   = !diff[32];

	always @(posedge clk) begin
		if (!resetn || !go) begin
			done    <= 1'b0;
			running <= 1'b0;
		end else if (running) begin
			if (count != 6'd0) begin
				rem   <= fits ? diff[31:0] : rem_sh[31:0];
				quot  <= {quot[30:0], fits};
				count <= count - 6'd1;
			end else begin
				y       <= want_rem ? (neg_r ? -rem : rem) : (neg_q ? -quot : quot);
				running <= 1'b0;
				done    <= 1'b1;
			end
		end else if (!done) begin
			if (!is_div) begin
				y    <= funct3[1:0] == 2'b00 ? prod[31:0] : prod[63:32];
				done <= 1'b1;
			end else if (b == 32'd0) begin
				y    <= want_rem ? a : 32'hFFFF_FFFF;
				done <= 1'b1;
			end else begin
				neg_q   <= signed_d && (a[31] ^ b[31]);
				neg_r   <= signed_d && a[31];
				quot    <= signed_d && a[31] ? -a : a;      // shifted into rem bit by bit
				divisor <= signed_d && b[31] ? -b : b;
				rem     <= 32'd0;
				count   <= 6'd32;
				running <= 1'b1;
			end
		end
	end

endmodule
