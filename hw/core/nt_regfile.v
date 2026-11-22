// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier register file: 31 x 32-bit, two asynchronous read ports and
// synchronous CPU/debug write ports. x0 always reads as zero.
//
// The read addresses come straight from the instruction register, so
// GowinSynthesis maps this to one BSRAM plus shadow SRAM (the same as
// the previous core); all 26 BSRAMs of the GW1NR-9 are in use.

`timescale 1 ns / 1 ps

module nt_regfile (
	input             clk,

	input      [ 4:0] raddr1,
	output     [31:0] rdata1,
	input      [ 4:0] raddr2,
	output     [31:0] rdata2,

	input             we,
	input      [ 4:0] waddr,
	input      [31:0] wdata,

	input             debug_we,
	input      [ 4:0] debug_waddr,
	input      [31:0] debug_wdata
);
	reg [31:0] regs [1:31];

	always @(posedge clk)
		if (debug_we && debug_waddr != 5'd0)
			regs[debug_waddr] <= debug_wdata;
		else if (we && waddr != 5'd0)
			regs[waddr] <= wdata;

	assign rdata1 = raddr1 == 5'd0 ? 32'd0 : regs[raddr1];
	assign rdata2 = raddr2 == 5'd0 ? 32'd0 : regs[raddr2];
endmodule
