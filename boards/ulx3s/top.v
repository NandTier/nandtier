// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier on the Radiona ULX3S (Lattice ECP5, 12F/25F/45F/85F).
//
//   clocks    25 MHz -> EHXPLLL: 125 MHz (HDMI shift clock, VCO 625 MHz)
//             and 25 MHz for the CPU, bus and pixels
//   flash     the SPI flash also holds the bitstream (from address 0), so
//             the firmware lives at 0x200000 (FLASH_OFFSET); its clock pin
//             is the configuration clock, reached through USRMCLK
//   HDMI      the GPDI connector, pseudo-differential (boards/common/
//             ecp5_hdmi_phy.v)
//   reset     the PWR button (BTN0), low while pressed
//   LEDs      LED0-6 = GPIO 0-6; they light on 1, so the GPIO pins are
//             inverted (the firmware drives active-low LEDs)
//   UART      through the FTDI USB bridge
//
// wifi_gpio0 is held high: the ESP32 then leaves the board alone.

`timescale 1 ns / 1 ps

module nt_ulx3s (
	input        clk_25mhz,
	input        btn_pwr_n,     // BTN0, active low

	output [3:0] gpdi_dp,       // 0-2 TMDS data, 3 TMDS clock

	input        sd_miso,       // sd_d[0]
	output       sd_cs,         // sd_d[3]
	output       sd_mosi,       // sd_cmd
	output       sd_clk,

	output       flash_csn,
	inout        flash_mosi,
	inout        flash_miso,
	output       flash_holdn,
	output       flash_wpn,

	input        ftdi_txd,      // from the PC
	output       ftdi_rxd,      // to the PC
	output       wifi_gpio0,

	inout  [6:0] led
);
	wire clk_5x, clk_sys, pll_lock;

	(* FREQUENCY_PIN_CLKI = "25" *)
	(* FREQUENCY_PIN_CLKOP = "125" *)
	(* FREQUENCY_PIN_CLKOS = "25" *)
	(* ICP_CURRENT = "12" *) (* LPF_RESISTOR = "8" *) (* MFG_ENABLE_FILTEROPAMP = "1" *) (* MFG_GMCREF_SEL = "2" *)
	EHXPLLL #(
		.PLLRST_ENA("DISABLED"), .INTFB_WAKE("DISABLED"), .STDBY_ENABLE("DISABLED"),
		.DPHASE_SOURCE("DISABLED"),
		.OUTDIVIDER_MUXA("DIVA"), .OUTDIVIDER_MUXB("DIVB"),
		.OUTDIVIDER_MUXC("DIVC"), .OUTDIVIDER_MUXD("DIVD"),
		.CLKI_DIV(1),
		.CLKOP_ENABLE("ENABLED"), .CLKOP_DIV(5), .CLKOP_CPHASE(2), .CLKOP_FPHASE(0),
		.CLKOS_ENABLE("ENABLED"), .CLKOS_DIV(25), .CLKOS_CPHASE(2), .CLKOS_FPHASE(0),
		.FEEDBK_PATH("CLKOP"), .CLKFB_DIV(5)
	) u_pll (
		.RST(1'b0), .STDBY(1'b0), .CLKI(clk_25mhz),
		.CLKOP(clk_5x), .CLKOS(clk_sys), .CLKOS2(), .CLKOS3(),
		.CLKFB(clk_5x), .CLKINTFB(),
		.PHASESEL0(1'b0), .PHASESEL1(1'b0), .PHASEDIR(1'b1), .PHASESTEP(1'b1),
		.PHASELOADREG(1'b1), .PLLWAKESYNC(1'b0), .ENCLKOP(1'b0),
		.LOCK(pll_lock), .ENCLKOS(), .ENCLKOS2(), .ENCLKOS3(), .INTLOCK(), .REFCLK()
	);

	// the flash clock pin is the FPGA's configuration clock
	wire flash_clk;
	USRMCLK u_mclk (.USRMCLKI(flash_clk), .USRMCLKTS(1'b0));

	assign flash_holdn = 1'b1;
	assign flash_wpn   = 1'b1;
	assign wifi_gpio0  = 1'b1;

	nandtier_soc #(
		.FLASH_OFFSET(24'h200000),
		.GPIO_INVERT (7'h7F),
		.ENABLE_ECP5_JTAG(1)
	) u_soc (
		.clk_sys(clk_sys), .clk_5x(clk_5x), .pll_lock(pll_lock), .resetn(btn_pwr_n),
		.tmds_clk_n(), .tmds_clk_p(gpdi_dp[3]), .tmds_d_n(), .tmds_d_p(gpdi_dp[2:0]),
		.sd_miso(sd_miso), .sd_cs(sd_cs), .sd_mosi(sd_mosi), .sd_clk(sd_clk),
		.flash_clk(flash_clk), .flash_csb(flash_csn), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
		.ser_rx(ftdi_txd), .ser_tx(ftdi_rxd), .gpio(led)
	);

endmodule
