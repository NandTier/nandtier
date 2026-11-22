// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier TMDS encoder (DVI 1.0, section 3.2): turns one 8-bit colour
// component per pixel into a 10-bit symbol, or a control symbol during
// blanking. Output bit 0 is sent first. One cycle of latency.
//
// Stage 1 picks XOR or XNOR chaining, whichever gives fewer transitions
// (q_m[8] records the choice). Stage 2 inverts the 8 data bits when that
// moves the running disparity of the line towards zero (bit 9 records
// it).

`timescale 1 ns / 1 ps

module nt_tmds_encoder (
	input            clk,
	input            resetn,
	input            de,        // 1: data, 0: control period
	input      [7:0] data,
	input      [1:0] ctrl,      // {C1, C0} during the control period
	output reg [9:0] symbol
);
	function [3:0] ones(input [7:0] x);
		integer i;
		begin
			ones = 4'd0;
			for (i = 0; i < 8; i = i + 1)
				ones = ones + {3'd0, x[i]};
		end
	endfunction

	// stage 1: transition minimisation
	wire use_xnor = ones(data) > 4'd4 || (ones(data) == 4'd4 && !data[0]);

	reg [8:0] q_m;
	integer i;
	always @* begin
		q_m[0] = data[0];
		for (i = 1; i < 8; i = i + 1)
			q_m[i] = use_xnor ? !(q_m[i-1] ^ data[i]) : (q_m[i-1] ^ data[i]);
		q_m[8] = !use_xnor;
	end

	// stage 2: DC balance. disparity = (#ones - #zeros) of q_m[7:0]
	wire        [5:0] twice_ones = {1'b0, ones(q_m[7:0]), 1'b0};       // 0..16
	wire signed [5:0] disp_wide  = $signed(twice_ones) - 6'sd8;      // -8..8
	wire signed [4:0] disparity  = disp_wide[4:0];
	reg  signed [4:0] bias;       // running disparity, in units of one bit

	wire bias_zero = bias == 5'sd0;
	wire balanced  = disparity == 5'sd0;
	wire same_sign = bias[4] == disparity[4];

	always @(posedge clk) begin
		if (!resetn) begin
			bias   <= 5'sd0;
			symbol <= 10'b1101010100;
		end else if (!de) begin
			bias <= 5'sd0;
			case (ctrl)
				2'b00: symbol <= 10'b1101010100;
				2'b01: symbol <= 10'b0010101011;
				2'b10: symbol <= 10'b0101010100;
				2'b11: symbol <= 10'b1010101011;
			endcase
		end else if (bias_zero || balanced) begin
			symbol <= {!q_m[8], q_m[8], q_m[8] ? q_m[7:0] : ~q_m[7:0]};
			bias   <= q_m[8] ? bias + disparity : bias - disparity;
		end else if (same_sign) begin
			// bias and data lean the same way: send the data inverted
			symbol <= {1'b1, q_m[8], ~q_m[7:0]};
			bias   <= bias - disparity + (q_m[8] ? 5'sd2 : 5'sd0);
		end else begin
			symbol <= {1'b0, q_m[8], q_m[7:0]};
			bias   <= bias + disparity - (q_m[8] ? 5'sd0 : 5'sd2);
		end
	end

endmodule
