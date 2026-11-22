// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Simulation stand-ins for the Gowin_rPLL and Gowin_CLKDIV IP wrappers
// (gowin_ip/), with the same ports: the PLL makes its own 124.875 MHz
// clock (27 MHz * 37 / 8) and locks after 1 us; CLKDIV divides by 5.

`timescale 1 ns / 1 ps

module Gowin_rPLL (
	input      clkin,
	output reg clkout,
	output reg lock
);
	initial begin
		clkout = 0;
		lock   = 0;
		#1000 lock = 1;
	end
	always #(1000.0 / 124.875 / 2) clkout = !clkout;
endmodule

module Gowin_CLKDIV (
	input      hclkin,
	input      resetn,
	output reg clkout
);
	reg [2:0] count = 0;
	initial clkout = 0;
	always @(posedge hclkin) begin
		if (!resetn) begin
			count  <= 0;
			clkout <= 0;
		end else begin
			count <= count == 4 ? 3'd0 : count + 3'd1;
			if (count == 4 || count == 1)       // 2 high, 3 low: same edges as /5
				clkout <= count == 4;
		end
	end
endmodule
