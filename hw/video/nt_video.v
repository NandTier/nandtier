// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier video output: 640x480 DVI/HDMI picture made of
//   - the nt_ppu tile and sprite picture (256 x 240, shown at 2x in the
//     middle), programmed through the ppu_* bus port
//   - the nt_text_term text screen drawn in white on top (can be switched
//     off with the PPU CTRL register), fed through term_*
//
// clk is both the system and the pixel clock; clk_5x (5x clk) drives the
// 10:1 serialisers in nt_hdmi_phy. The nt_hdmi_phy below is the Gowin one
// (OSER10 and an LVDS output buffer per lane, emulated or, with TRUE_LVDS,
// true LVDS). Boards with other FPGAs define NT_HDMI_PHY_EXTERNAL and bring
// their own nt_hdmi_phy with the same ports (boards/common/).

`timescale 1 ns / 1 ps

module nt_video #(
	parameter TRUE_LVDS = 0         // Gowin: TLVDS_OBUF instead of ELVDS_OBUF
) (
	input        clk,
	input        clk_5x,
	input        resetn,

	input        term_valid,
	input  [7:0] term_char,
	output       term_ready,

	input        ppu_valid,
	input [15:0] ppu_addr,
	input [31:0] ppu_wdata,
	input  [3:0] ppu_wstrb,
	output       ppu_ready,
	output [31:0] ppu_rdata,

	output       tmds_clk_p,
	output       tmds_clk_n,
	output [2:0] tmds_d_p,
	output [2:0] tmds_d_n
);
	// --- t+0: pixel position ---------------------------------------------------

	wire [9:0] x, y;
	wire       visible, hsync, vsync;

	nt_video_timing u_timing (
		.clk(clk), .resetn(resetn),
		.x(x), .y(y), .visible(visible), .hsync(hsync), .vsync(vsync)
	);

	// --- tiles and sprites: colour at t+3 ---------------------------------------

	wire [11:0] ppu_rgb;
	wire        ppu_active, term_enabled;

	nt_ppu u_ppu (
		.clk(clk), .resetn(resetn),
		.valid(ppu_valid), .addr(ppu_addr), .wdata(ppu_wdata), .wstrb(ppu_wstrb),
		.ready(ppu_ready), .rdata(ppu_rdata),
		.x(x), .y(y), .rgb(ppu_rgb), .active(ppu_active), .term_on(term_enabled)
	);

	// --- text: text_on at t+3 ----------------------------------------------------

	wire text_on;

	nt_text_term u_term (
		.clk(clk), .resetn(resetn),
		.in_valid(term_valid), .in_char(term_char), .in_ready(term_ready),
		.x(x), .y(y), .text_on(text_on)
	);

	// --- line everything up at t+3, colour register at t+4 --------------------

	reg [3:0] vis_d, hs_d, vs_d;

	always @(posedge clk) begin
		vis_d <= {vis_d[2:0], visible};
		hs_d  <= {hs_d[2:0], hsync};
		vs_d  <= {vs_d[2:0], vsync};
	end

	// 4-bit colour channels doubled up to 8 bits; black outside the picture
	wire white = text_on && term_enabled;
	reg  [7:0] red, green, blue;

	always @(posedge clk) begin
		red   <= white ? 8'hFF : ppu_active ? {2{ppu_rgb[11:8]}} : 8'd0;
		green <= white ? 8'hFF : ppu_active ? {2{ppu_rgb[ 7:4]}} : 8'd0;
		blue  <= white ? 8'hFF : ppu_active ? {2{ppu_rgb[ 3:0]}} : 8'd0;
	end

	// --- t+5: TMDS symbols (lane 0 = blue + sync, 1 = green, 2 = red) ----------

	wire [9:0] sym_blue, sym_green, sym_red;

	nt_tmds_encoder u_enc_blue  (.clk(clk), .resetn(resetn), .de(vis_d[3]), .data(blue),
	                             .ctrl({vs_d[3], hs_d[3]}), .symbol(sym_blue));
	nt_tmds_encoder u_enc_green (.clk(clk), .resetn(resetn), .de(vis_d[3]), .data(green),
	                             .ctrl(2'b00), .symbol(sym_green));
	nt_tmds_encoder u_enc_red   (.clk(clk), .resetn(resetn), .de(vis_d[3]), .data(red),
	                             .ctrl(2'b00), .symbol(sym_red));

	// --- serialise and drive the pins ------------------------------------------------

	nt_hdmi_phy #(
		.TRUE_LVDS(TRUE_LVDS)
	) u_phy (
		.clk(clk), .clk_5x(clk_5x), .resetn(resetn),
		.sym0(sym_blue), .sym1(sym_green), .sym2(sym_red),
		.tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
		.tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
	);

endmodule

`ifndef NT_HDMI_PHY_EXTERNAL

// Gowin: an OSER10 per lane (bit 0 first) and an LVDS output buffer. The
// clock lane sends 0000011111, the pixel clock.
module nt_hdmi_phy #(
	parameter TRUE_LVDS = 0
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
	wire [9:0] lane [0:3];
	assign lane[0] = sym0;
	assign lane[1] = sym1;
	assign lane[2] = sym2;
	assign lane[3] = 10'b0000011111;

	wire [3:0] serial;

	genvar n;
	generate
		for (n = 0; n < 4; n = n + 1) begin : tmds_lane
			OSER10 u_ser (
				.Q(serial[n]),
				.D0(lane[n][0]), .D1(lane[n][1]), .D2(lane[n][2]), .D3(lane[n][3]), .D4(lane[n][4]),
				.D5(lane[n][5]), .D6(lane[n][6]), .D7(lane[n][7]), .D8(lane[n][8]), .D9(lane[n][9]),
				.PCLK(clk), .FCLK(clk_5x), .RESET(!resetn)
			);
		end

		// one instance per pair, wired straight to the pins (the open-source
		// flow needs the direct connection to see both pins as one pair)
		if (TRUE_LVDS) begin : tlvds
			TLVDS_OBUF u_out_d0  (.I(serial[0]), .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
			TLVDS_OBUF u_out_d1  (.I(serial[1]), .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
			TLVDS_OBUF u_out_d2  (.I(serial[2]), .O(tmds_d_p[2]), .OB(tmds_d_n[2]));
			TLVDS_OBUF u_out_clk (.I(serial[3]), .O(tmds_clk_p),  .OB(tmds_clk_n));
		end else begin : elvds
			ELVDS_OBUF u_out_d0  (.I(serial[0]), .O(tmds_d_p[0]), .OB(tmds_d_n[0]));
			ELVDS_OBUF u_out_d1  (.I(serial[1]), .O(tmds_d_p[1]), .OB(tmds_d_n[1]));
			ELVDS_OBUF u_out_d2  (.I(serial[2]), .O(tmds_d_p[2]), .OB(tmds_d_n[2]));
			ELVDS_OBUF u_out_clk (.I(serial[3]), .O(tmds_clk_p),  .OB(tmds_clk_n));
		end
	endgenerate

endmodule

`endif
