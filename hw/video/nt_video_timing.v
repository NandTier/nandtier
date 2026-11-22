// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier video timing: pixel counters and sync for 640x480 at 60 Hz
// (VESA DMT, 25.175 MHz nominal pixel clock; this SoC runs it from its
// 24.975 MHz system clock, 59.5 Hz). All outputs are registered and
// belong to the same pixel.
//
//            visible  front porch  sync  back porch  total
//   horiz.   640      16           96    48          800
//   vert.    480      10           2     33          525

`timescale 1 ns / 1 ps

module nt_video_timing #(
	parameter H_VISIBLE = 640, H_FRONT = 16, H_SYNC = 96, H_BACK = 48,
	parameter V_VISIBLE = 480, V_FRONT = 10, V_SYNC = 2,  V_BACK = 33,
	parameter SYNC_ACTIVE = 1'b0          // sync pulse level (VESA: negative)
) (
	input            clk,
	input            resetn,
	output reg [9:0] x,         // 0 .. H total - 1
	output reg [9:0] y,         // 0 .. V total - 1
	output reg       visible,
	output reg       hsync,
	output reg       vsync
);
	localparam H_TOTAL = H_VISIBLE + H_FRONT + H_SYNC + H_BACK;
	localparam V_TOTAL = V_VISIBLE + V_FRONT + V_SYNC + V_BACK;

	wire       x_last = x == H_TOTAL - 1;
	wire       y_last = y == V_TOTAL - 1;
	wire [9:0] nx     = x_last ? 10'd0 : x + 10'd1;
	wire [9:0] ny     = !x_last ? y : y_last ? 10'd0 : y + 10'd1;

	always @(posedge clk) begin
		if (!resetn) begin
			x       <= 10'd0;
			y       <= 10'd0;
			visible <= 1'b1;
			hsync   <= !SYNC_ACTIVE;
			vsync   <= !SYNC_ACTIVE;
		end else begin
			x       <= nx;
			y       <= ny;
			visible <= nx < H_VISIBLE && ny < V_VISIBLE;
			hsync   <= (nx >= H_VISIBLE + H_FRONT && nx < H_VISIBLE + H_FRONT + H_SYNC) ?
			           SYNC_ACTIVE : !SYNC_ACTIVE;
			vsync   <= (ny >= V_VISIBLE + V_FRONT && ny < V_VISIBLE + V_FRONT + V_SYNC) ?
			           SYNC_ACTIVE : !SYNC_ACTIVE;
		end
	end

endmodule
