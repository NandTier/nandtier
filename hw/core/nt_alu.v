// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier ALU (purely combinational).
//
// op is {alt, funct3}, i.e. the RISC-V OP/OP-IMM encoding itself:
//   0000 ADD   1000 SUB   0001 SLL   0010 SLT   0011 SLTU
//   0100 XOR   0101 SRL   1101 SRA   0110 OR    0111 AND
//
// ADD, SUB, SLT and SLTU share one adder; SLL reuses the right shifter
// by bit-reversing its input and output.

`timescale 1 ns / 1 ps

module nt_alu (
	input      [ 3:0] op,
	input      [31:0] a,
	input      [31:0] b,
	output reg [31:0] y
);
	wire        alt = op[3];
	wire [ 2:0] f3  = op[2:0];

	// a - b for SUB/SLT/SLTU, a + b otherwise
	wire        sub = alt || f3 == 3'b010 || f3 == 3'b011;
	wire [32:0] sum = {1'b0, a} + {1'b0, sub ? ~b : b} + {32'd0, sub};

	wire        ltu = !sum[32];
	wire        lt  = a[31] != b[31] ? a[31] : sum[31];

	function [31:0] reverse(input [31:0] x);
		integer i;
		for (i = 0; i < 32; i = i + 1)
			reverse[i] = x[31 - i];
	endfunction

	wire        left    = f3 == 3'b001;
	wire [31:0] sh_in   = left ? reverse(a) : a;
	wire        sh_fill = alt && a[31];
	wire [32:0] sh_wide = $signed({sh_fill, sh_in}) >>> b[4:0];
	wire [31:0] sh_out  = sh_wide[31:0];

	always @* begin
		case (f3)
			3'b000:  y = sum[31:0];
			3'b001:  y = reverse(sh_out);
			3'b010:  y = {31'b0, lt};
			3'b011:  y = {31'b0, ltu};
			3'b100:  y = a ^ b;
			3'b101:  y = sh_out;
			3'b110:  y = a | b;
			default: y = a & b;
		endcase
	end

endmodule
