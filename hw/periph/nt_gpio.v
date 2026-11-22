// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier GPIO: WIDTH bidirectional pins.
//
// INVERT flips pins between the registers and the board (bit n for pin n),
// e.g. for LEDs that light on 1 where the firmware expects active-low LEDs.
//
// Registers (bit n controls pin n):
//   +0x0 OUT  output value
//   +0x4 IN   pin state (read only, synchronised to clk)
//   +0x8 OE   output enable, 1 = drive the pin from OUT
//
// The bus answers one cycle after valid.

`timescale 1 ns / 1 ps

module nt_gpio #(
	parameter             WIDTH  = 7,
	parameter [WIDTH-1:0] INVERT = 0
) (
	input                  clk,
	input                  resetn,

	input                  valid,
	input      [31:0]      addr,
	input      [31:0]      wdata,
	input      [ 3:0]      wstrb,
	output reg             ready,
	output reg [31:0]      rdata,

	inout      [WIDTH-1:0] io
);
	reg  [31:0] out, oe;
	reg  [WIDTH-1:0] in_meta, in_sync;

	function [31:0] merge(input [31:0] old, input [31:0] upd, input [3:0] strb);
		integer b;
		for (b = 0; b < 4; b = b + 1)
			merge[b*8 +: 8] = strb[b] ? upd[b*8 +: 8] : old[b*8 +: 8];
	endfunction

	always @(posedge clk) begin
		in_meta <= io ^ INVERT;
		in_sync <= in_meta;
		ready   <= 1'b0;

		if (!resetn) begin
			out <= 32'd0;
			oe  <= 32'd0;
		end else if (valid && !ready) begin
			ready <= 1'b1;
			case (addr[3:2])
				2'd0: begin
					out   <= merge(out, wdata, wstrb);
					rdata <= out;
				end
				2'd1:    rdata <= {{(32-WIDTH){1'b0}}, in_sync};
				2'd2: begin
					oe    <= merge(oe, wdata, wstrb);
					rdata <= oe;
				end
				default: rdata <= 32'd0;
			endcase
		end
	end

	genvar n;
	generate
		for (n = 0; n < WIDTH; n = n + 1) begin : pin
			assign io[n] = oe[n] ? out[n] ^ INVERT[n] : 1'bz;
		end
	endgenerate

endmodule
