// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier on the Sipeed Tang Nano 20K (Gowin GW2AR-18C).
//
//   clocks    27 MHz -> rPLL 124.875 MHz (27 * 37 / 8; VCO 999 MHz, inside
//             the GW2A's 500-1250 MHz) -> CLKDIV /5 -> 24.975 MHz
//   flash     the 8 MiB SPI flash also holds the bitstream (from address 0),
//             so the firmware lives at 0x100000 (FLASH_OFFSET)
//   HDMI      true LVDS pairs (TLVDS_OBUF)
//   reset     S1 (pin 88), high while pressed
//   LEDs      LED0-5 = GPIO 0-5 (active low, like the Tang Nano 9K);
//             GPIO 6 has no pin here

`timescale 1 ns / 1 ps

module nt_tangnano20k (
	input        clk,           // 27 MHz
	input        btn_s1,        // reset, active high

	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p,

	input        sd_miso,
	output       sd_cs,
	output       sd_mosi,
	output       sd_clk,

	output       flash_clk,
	output       flash_csb,
	inout        flash_mosi,
	inout        flash_miso,

	input        ser_rx,
	output       ser_tx,
	inout  [5:0] led
);
	wire clk_5x, clk_sys, pll_lock;

	rPLL #(
		.FCLKIN   ("27"),
		.IDIV_SEL (7),              // / 8
		.FBDIV_SEL(36),             // * 37
		.ODIV_SEL (8),              // VCO = 124.875 MHz * 8 = 999 MHz
		.DEVICE   ("GW2AR-18C")
	) u_pll (
		.CLKOUT(clk_5x), .LOCK(pll_lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
		.RESET(1'b0), .RESET_P(1'b0), .CLKIN(clk), .CLKFB(1'b0),
		.FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0),
		.PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
	);

	CLKDIV #(
		.DIV_MODE("5")
	) u_div (
		.CLKOUT(clk_sys), .HCLKIN(clk_5x), .RESETN(pll_lock), .CALIB(1'b0)
	);

	wire gpio6;

	nandtier_soc #(
		.FLASH_OFFSET(24'h100000),
		.TRUE_LVDS   (1)
	) u_soc (
		.clk_sys(clk_sys), .clk_5x(clk_5x), .pll_lock(pll_lock), .resetn(!btn_s1),
		.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
		.sd_miso(sd_miso), .sd_cs(sd_cs), .sd_mosi(sd_mosi), .sd_clk(sd_clk),
		.flash_clk(flash_clk), .flash_csb(flash_csb), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
		.ser_rx(ser_rx), .ser_tx(ser_tx), .gpio({gpio6, led})
	);

endmodule
