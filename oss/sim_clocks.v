// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Stand-ins for the rPLL and CLKDIV primitives in the gate-level
// simulation (make gatesim): the Gowin rPLL simulation model does not run
// under Icarus Verilog (no output clock). Same ports and outputs as the
// primitives, for this design's settings: rPLL 27 MHz * 37 / 8 = 124.875
// MHz, locked after 1 us; CLKDIV divides by 5. The Makefile renames the two
// instances in a copy of the netlist to use these.

`timescale 1 ns / 1 ps

module nt_sim_rPLL #(
	parameter FCLKIN = "27", parameter IDIV_SEL = 0, parameter FBDIV_SEL = 0,
	parameter ODIV_SEL = 8, parameter DEVICE = "", parameter CLKFB_SEL = "internal",
	parameter DYN_SDIV_SEL = 2, parameter DUTYDA_SEL = "1000", parameter PSDA_SEL = "0000",
	parameter DYN_DA_EN = "false", parameter DYN_IDIV_SEL = "false", parameter DYN_FBDIV_SEL = "false",
	parameter DYN_ODIV_SEL = "false", parameter CLKOUT_FT_DIR = 1'b1, parameter CLKOUTP_FT_DIR = 1'b1,
	parameter CLKOUT_DLY_STEP = 0, parameter CLKOUTP_DLY_STEP = 0, parameter CLKOUT_BYPASS = "false",
	parameter CLKOUTP_BYPASS = "false", parameter CLKOUTD_BYPASS = "false",
	parameter CLKOUTD_SRC = "CLKOUT", parameter CLKOUTD3_SRC = "CLKOUT"
) (
	input            CLKIN, CLKFB, RESET, RESET_P,
	input      [5:0] FBDSEL, IDSEL, ODSEL,
	input      [3:0] PSDA, DUTYDA, FDLY,
	output reg       CLKOUT = 0,
	output           CLKOUTP, CLKOUTD, CLKOUTD3,
	output reg       LOCK = 0
);
	// output frequency from the settings: FCLKIN * (FBDIV_SEL + 1) / (IDIV_SEL + 1)
	localparam real F_MHZ = 27.0 * (FBDIV_SEL + 1) / (IDIV_SEL + 1);
	initial #1000 LOCK = 1;
	always #(1000.0 / F_MHZ / 2) CLKOUT = !CLKOUT;
	assign CLKOUTP = CLKOUT;
	assign CLKOUTD = 1'b0;
	assign CLKOUTD3 = 1'b0;
endmodule

module nt_sim_CLKDIV #(
	parameter DIV_MODE = "5", parameter GSREN = "false"
) (
	input      HCLKIN,
	input      RESETN,
	input      CALIB,
	output reg CLKOUT = 0
);
	reg [2:0] count = 0;
	always @(posedge HCLKIN) begin
		if (!RESETN) begin
			count  <= 0;
			CLKOUT <= 0;
		end else begin
			count <= count == 4 ? 3'd0 : count + 3'd1;
			if (count == 4 || count == 1)
				CLKOUT <= count == 4;
		end
	end
endmodule
