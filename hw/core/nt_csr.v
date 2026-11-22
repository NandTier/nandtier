// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier CSR unit: the read-only 64-bit counters
//   0xC00 cycle   0xC01 time (= cycle)   0xC02 instret
//   0xC80 cycleh  0xC81 timeh            0xC82 instreth
// valid is low for any other address, which the core treats as an
// illegal instruction.

`timescale 1 ns / 1 ps

module nt_csr (
	input             clk,
	input             resetn,
	input             retire,

	input      [11:0] addr,
	output reg [31:0] rdata,
	output reg        valid
);
	reg [63:0] cycle;
	reg [63:0] instret;

	always @(posedge clk) begin
		if (!resetn) begin
			cycle   <= 64'd0;
			instret <= 64'd0;
		end else begin
			cycle <= cycle + 64'd1;
			if (retire)
				instret <= instret + 64'd1;
		end
	end

	always @* begin
		valid = 1'b1;
		case (addr)
			12'hC00, 12'hC01: rdata = cycle[31:0];
			12'hC02:          rdata = instret[31:0];
			12'hC80, 12'hC81: rdata = cycle[63:32];
			12'hC82:          rdata = instret[63:32];
			default: begin
				rdata = 32'd0;
				valid = 1'b0;
			end
		endcase
	end

endmodule
