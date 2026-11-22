// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier branch comparator (purely combinational).
// funct3 is the BRANCH funct3: BEQ, BNE, BLT, BGE, BLTU, BGEU.
// The two reserved encodings (010, 011) never reach here, the
// decoder flags them as illegal.

`timescale 1 ns / 1 ps

module nt_branch (
	input      [ 2:0] funct3,
	input      [31:0] a,
	input      [31:0] b,
	output reg        taken
);
	wire eq  = a == b;
	wire lt  = $signed(a) < $signed(b);
	wire ltu = a < b;

	always @* begin
		case (funct3[2:1])
			2'b00:   taken = eq;
			2'b10:   taken = lt;
			2'b11:   taken = ltu;
			default: taken = 1'b0;
		endcase
		if (funct3[0])
			taken = !taken;
	end

endmodule
