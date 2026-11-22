// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier memory interface: puts fetch and load/store requests on the
// single valid/ready bus.
//
// A request (if_req or ls_req, never both, never while busy) registers
// the address/data and raises mem_valid. mem_valid and mem_wstrb drop on
// the clock edge where mem_ready is seen, so every transfer is followed
// by at least one idle cycle. Slaves rely on this: some answer with a
// combinational ready, the block RAMs use valid & ~ready as clock enable.

`timescale 1 ns / 1 ps

module nt_bus (
	input             clk,
	input             resetn,

	input             if_req,
	input      [31:0] if_addr,

	input             ls_req,
	input      [31:0] ls_addr,
	input      [31:0] ls_wdata,
	input      [ 3:0] ls_wstrb,

	output            done,
	output     [31:0] rdata,

	output reg        mem_valid,
	output reg        mem_instr,
	input             mem_ready,
	output reg [31:0] mem_addr,
	output reg [31:0] mem_wdata,
	output reg [ 3:0] mem_wstrb,
	input      [31:0] mem_rdata
);
	assign done  = mem_valid && mem_ready;
	assign rdata = mem_rdata;

	always @(posedge clk) begin
		if (!resetn) begin
			mem_valid <= 1'b0;
			mem_instr <= 1'b0;
			mem_wstrb <= 4'b0000;
		end else if (done) begin
			mem_valid <= 1'b0;
			mem_wstrb <= 4'b0000;
		end else if (if_req) begin
			mem_valid <= 1'b1;
			mem_instr <= 1'b1;
			mem_addr  <= if_addr;
			mem_wstrb <= 4'b0000;
		end else if (ls_req) begin
			mem_valid <= 1'b1;
			mem_instr <= 1'b0;
			mem_addr  <= ls_addr;
			mem_wdata <= ls_wdata;
			mem_wstrb <= ls_wstrb;
		end
	end

endmodule
