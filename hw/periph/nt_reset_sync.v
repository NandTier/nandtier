// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier reset synchroniser: resetn follows ext_resetn low at once and
// goes high HOLD_CYCLES clock cycles after ext_resetn is released,
// synchronously to clk.

`timescale 1 ns / 1 ps

module nt_reset_sync #(
	parameter HOLD_CYCLES = 16
) (
	input  clk,
	input  ext_resetn,
	output resetn
);
	reg [HOLD_CYCLES-1:0] hold = {HOLD_CYCLES{1'b0}};

	always @(posedge clk or negedge ext_resetn) begin
		if (!ext_resetn)
			hold <= {HOLD_CYCLES{1'b0}};
		else
			hold <= {hold[HOLD_CYCLES-2:0], 1'b1};
	end

	assign resetn = hold[HOLD_CYCLES-1];

endmodule
