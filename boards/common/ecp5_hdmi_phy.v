// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// HDMI output stage for Lattice ECP5 boards (build with
// NT_HDMI_PHY_EXTERNAL, see hw/video/nt_video.v): the same ports as the
// Gowin nt_hdmi_phy.
//
// Each lane is a 10-bit shift register in the clk_5x domain sending two
// bits per clock through an ODDRX1F (DDR output), bit 0 first, so clk_5x
// is 5x the pixel clock. The pins are pseudo-differential (LVCMOS33D in
// the board's LPF): only the _p outputs are used, the FPGA drives the
// complementary pin itself.
//
// Crossing from the pixel clock: clk is held in hold0-2 every pixel and a
// flag toggles with it. The flag goes through two flip-flops in the clk_5x
// domain; its change loads the shift registers 2-3 fast clocks after the
// pixel edge, while hold0-2 are stable (they change every 5 fast clocks).
// Both clocks come from the same PLL, so this happens every 5th clock.

`timescale 1 ns / 1 ps

module nt_hdmi_phy #(
	parameter TRUE_LVDS = 0         // not used on ECP5
) (
	input        clk,
	input        clk_5x,
	input        resetn,
	input  [9:0] sym0,
	input  [9:0] sym1,
	input  [9:0] sym2,
	output       tmds_clk_p,
	output       tmds_clk_n,
	output [2:0] tmds_d_p,
	output [2:0] tmds_d_n
);
	// --- pixel clock domain ---------------------------------------------------

	reg [9:0] hold0, hold1, hold2;
	reg       flag = 1'b0;

	always @(posedge clk) begin
		hold0 <= sym0;
		hold1 <= sym1;
		hold2 <= sym2;
		flag  <= !flag;
	end

	// --- clk_5x domain --------------------------------------------------------

	reg [2:0] flag_sync = 3'b000;
	reg [9:0] sh0, sh1, sh2, sh3;

	always @(posedge clk_5x) begin
		flag_sync <= {flag_sync[1:0], flag};
		if (flag_sync[2] != flag_sync[1]) begin
			sh0 <= hold0;
			sh1 <= hold1;
			sh2 <= hold2;
			sh3 <= 10'b0000011111;          // the pixel clock
		end else begin
			sh0 <= sh0 >> 2;
			sh1 <= sh1 >> 2;
			sh2 <= sh2 >> 2;
			sh3 <= sh3 >> 2;
		end
	end

	ODDRX1F u_ddr0 (.D0(sh0[0]), .D1(sh0[1]), .SCLK(clk_5x), .RST(1'b0), .Q(tmds_d_p[0]));
	ODDRX1F u_ddr1 (.D0(sh1[0]), .D1(sh1[1]), .SCLK(clk_5x), .RST(1'b0), .Q(tmds_d_p[1]));
	ODDRX1F u_ddr2 (.D0(sh2[0]), .D1(sh2[1]), .SCLK(clk_5x), .RST(1'b0), .Q(tmds_d_p[2]));
	ODDRX1F u_ddr3 (.D0(sh3[0]), .D1(sh3[1]), .SCLK(clk_5x), .RST(1'b0), .Q(tmds_clk_p));

	assign tmds_clk_n = 1'b0;           // not connected to pins (pseudo-differential)
	assign tmds_d_n   = 3'b000;

endmodule
