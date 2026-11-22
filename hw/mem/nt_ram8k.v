// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier 8 KiB RAMs on the bus, built from four 2048 x 8 Gowin block
// RAMs (one per byte lane, so byte writes need no read-modify-write).
//
//   nt_boot_ram  bootram_2kx8_0..3: initialised with the boot ROM image
//                (project/src/gowin_sp, see sw/update_bootram_init.py)
//   nt_sram      sram_2kx8: uninitialised work RAM
//
// The bus answers one cycle after valid; the block RAMs are enabled only
// in the first cycle of an access (valid && !ready).

`timescale 1 ns / 1 ps

module nt_boot_ram (
	input         clk,
	input         resetn,
	input         valid,
	input  [31:0] addr,
	input  [31:0] wdata,
	input  [ 3:0] wstrb,
	output reg    ready,
	output [31:0] rdata
);
	wire ce = valid && !ready;

	always @(posedge clk)
		ready <= resetn && ce;

	bootram_2kx8_0 u_lane0 (.clk(clk), .reset(!resetn), .ce(ce), .oce(1'b1), .wre(wstrb[0]),
	                        .ad(addr[12:2]), .din(wdata[ 7: 0]), .dout(rdata[ 7: 0]));
	bootram_2kx8_1 u_lane1 (.clk(clk), .reset(!resetn), .ce(ce), .oce(1'b1), .wre(wstrb[1]),
	                        .ad(addr[12:2]), .din(wdata[15: 8]), .dout(rdata[15: 8]));
	bootram_2kx8_2 u_lane2 (.clk(clk), .reset(!resetn), .ce(ce), .oce(1'b1), .wre(wstrb[2]),
	                        .ad(addr[12:2]), .din(wdata[23:16]), .dout(rdata[23:16]));
	bootram_2kx8_3 u_lane3 (.clk(clk), .reset(!resetn), .ce(ce), .oce(1'b1), .wre(wstrb[3]),
	                        .ad(addr[12:2]), .din(wdata[31:24]), .dout(rdata[31:24]));

endmodule

module nt_sram (
	input         clk,
	input         resetn,
	input         valid,
	input  [31:0] addr,
	input  [31:0] wdata,
	input  [ 3:0] wstrb,
	output reg    ready,
	output [31:0] rdata
);
	wire ce = valid && !ready;

	always @(posedge clk)
		ready <= resetn && ce;

	genvar lane;
	generate
		for (lane = 0; lane < 4; lane = lane + 1) begin : byte_lane
			sram_2kx8 u_ram (.clk(clk), .reset(!resetn), .ce(ce), .oce(1'b1), .wre(wstrb[lane]),
			                 .ad(addr[12:2]), .din(wdata[lane*8 +: 8]), .dout(rdata[lane*8 +: 8]));
		end
	endgenerate

endmodule
