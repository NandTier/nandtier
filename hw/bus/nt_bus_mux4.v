// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier bus decoder: one master, four slaves, purely combinational.
//
// Slave n is selected when (m_addr & MASKn) == (BASEn & MASKn); if
// several match, the lowest n wins. An access that matches no slave is
// acknowledged at once with read data 0, so a stray pointer cannot hang
// the CPU.
//
// The slave ports carry the master's address and write data unchanged;
// only valid is gated per slave.

`timescale 1 ns / 1 ps

module nt_bus_mux4 #(
	parameter [31:0] BASE0 = 32'h0000_0000, MASK0 = 32'hC000_0000,
	parameter [31:0] BASE1 = 32'h4000_0000, MASK1 = 32'hC000_0000,
	parameter [31:0] BASE2 = 32'h8000_0000, MASK2 = 32'hC000_0000,
	parameter [31:0] BASE3 = 32'hC000_0000, MASK3 = 32'hC000_0000
) (
	input             m_valid,
	input      [31:0] m_addr,
	output            m_ready,
	output     [31:0] m_rdata,

	output     [ 3:0] s_valid,      // bit n: slave n
	input      [ 3:0] s_ready,
	input      [31:0] s0_rdata,
	input      [31:0] s1_rdata,
	input      [31:0] s2_rdata,
	input      [31:0] s3_rdata
);
	wire [3:0] hit = {(m_addr & MASK3) == (BASE3 & MASK3),
	                  (m_addr & MASK2) == (BASE2 & MASK2),
	                  (m_addr & MASK1) == (BASE1 & MASK1),
	                  (m_addr & MASK0) == (BASE0 & MASK0)};

	// one-hot, lowest index first
	wire [3:0] sel = hit & ~(hit - 4'd1);

	assign s_valid = {4{m_valid}} & sel;

	assign m_ready = sel == 4'd0 ? m_valid : |(s_ready & sel);

	assign m_rdata = ({32{sel[0]}} & s0_rdata) |
	                 ({32{sel[1]}} & s1_rdata) |
	                 ({32{sel[2]}} & s2_rdata) |
	                 ({32{sel[3]}} & s3_rdata);

endmodule
