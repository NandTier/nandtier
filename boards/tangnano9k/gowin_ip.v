// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Tang Nano 9K clocks for the open-source flow: the Gowin_rPLL and
// Gowin_CLKDIV modules hw/nandtier.v uses, built from the rPLL and CLKDIV
// primitives (the Gowin IDE project uses the generated IP in gowin_ip/).
//
//   Gowin_rPLL    27 MHz -> 124.875 MHz (27 * 37 / 8, VCO 499.5 MHz)
//   Gowin_CLKDIV  divide by 5 -> 24.975 MHz

`timescale 1 ns / 1 ps

module Gowin_rPLL (
	output clkout,
	output lock,
	input  clkin
);
	rPLL #(
		.FCLKIN        ("27"),
		.DYN_IDIV_SEL  ("false"),
		.IDIV_SEL      (7),             // / 8
		.DYN_FBDIV_SEL ("false"),
		.FBDIV_SEL     (36),            // * 37
		.DYN_ODIV_SEL  ("false"),
		.ODIV_SEL      (4),             // VCO = 124.875 MHz * 4 = 499.5 MHz
		.PSDA_SEL      ("0000"),
		.DYN_DA_EN     ("true"),
		.DUTYDA_SEL    ("1000"),
		.CLKOUT_FT_DIR (1'b1),
		.CLKOUTP_FT_DIR(1'b1),
		.CLKOUT_DLY_STEP (0),
		.CLKOUTP_DLY_STEP(0),
		.CLKFB_SEL     ("internal"),
		.CLKOUT_BYPASS ("false"),
		.CLKOUTP_BYPASS("false"),
		.CLKOUTD_BYPASS("false"),
		.DYN_SDIV_SEL  (2),
		.CLKOUTD_SRC   ("CLKOUT"),
		.CLKOUTD3_SRC  ("CLKOUT"),
		.DEVICE        ("GW1NR-9C")
	) u_pll (
		.CLKOUT(clkout), .LOCK(lock), .CLKOUTP(), .CLKOUTD(), .CLKOUTD3(),
		.RESET(1'b0), .RESET_P(1'b0), .CLKIN(clkin), .CLKFB(1'b0),
		.FBDSEL(6'd0), .IDSEL(6'd0), .ODSEL(6'd0),
		.PSDA(4'd0), .DUTYDA(4'd0), .FDLY(4'd0)
	);
endmodule

module Gowin_CLKDIV (
	output clkout,
	input  hclkin,
	input  resetn
);
	CLKDIV #(
		.DIV_MODE("5"),
		.GSREN   ("false")
	) u_div (
		.CLKOUT(clkout), .HCLKIN(hclkin), .RESETN(resetn), .CALIB(1'b0)
	);
endmodule
