// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier fetch stage: program counter and instruction register.
//
// The PC is updated when an instruction commits (pc_we). The fetch
// request always goes to the PC value being loaded, so fetch_addr is
// next_pc on a commit and the current PC otherwise (first fetch after
// reset).

`timescale 1 ns / 1 ps

module nt_fetch #(
	parameter [31:0] RESET_PC = 32'h0000_0000
) (
	input             clk,
	input             resetn,

	input             pc_we,
	input      [31:0] next_pc,
	input             debug_pc_we,
	input      [31:0] debug_pc,
	output     [31:0] fetch_addr,

	input             ir_we,
	input      [31:0] ir_in,

	output reg [31:0] pc,
	output reg [31:0] ir
);
	assign fetch_addr = pc_we ? next_pc : pc;

	always @(posedge clk) begin
		if (!resetn)
			pc <= RESET_PC;
		else if (debug_pc_we)
			pc <= debug_pc;
		else if (pc_we)
			pc <= next_pc;

		if (ir_we)
			ir <= ir_in;
	end

endmodule
