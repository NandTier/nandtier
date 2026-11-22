// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier flash read cache, between the bus and nt_spi_flash: 4 KiB,
// direct mapped, 256 lines of 16 bytes (4 words).
//
//   hit:   ready one cycle after valid (like the SRAM)
//   miss:  the 4 words of the line are read from the flash in order (the
//          flash controller streams them), then the access completes
//   write: passed through to the flash port (nt_spi_flash ignores them)
//
// invalidate empties the cache (256 cycles, accesses wait); connect it to
// the flash controller's restart, so code is re-read after the flash was
// programmed. It also runs after reset.
//
// Address: bits 23:12 tag, 11:4 line, 3:2 word.

`timescale 1 ns / 1 ps

module nt_flash_cache (
	input             clk,
	input             resetn,
	input             invalidate,

	input             valid,
	input      [23:0] addr,
	input      [ 3:0] wstrb,
	output            ready,
	output     [31:0] rdata,

	output            f_valid,
	output     [23:0] f_addr,
	output     [ 3:0] f_wstrb,
	input             f_ready,
	input      [31:0] f_rdata
);
	localparam [1:0] C_IDLE = 2'd0, C_CHECK = 2'd1, C_FILL = 2'd2, C_CLEAR = 2'd3;

	reg  [1:0]  state;
	reg  [1:0]  fill_word;
	reg  [7:0]  clear_line;

	wire        is_write = |wstrb;
	wire [11:0] tag  = addr[23:12];
	wire [7:0]  line = addr[11:4];

	// --- memories: data 1024 x 32, tags 256 x {valid, tag} ---------------------------

	reg  [31:0] data [0:1023];
	reg  [12:0] tags [0:255];
	reg  [31:0] data_q;
	reg  [12:0] tag_q;

	wire        data_we = state == C_FILL && f_ready;
	wire [9:0]  data_wa = {line, fill_word};
	wire        tag_we  = state == C_CLEAR || (data_we && fill_word == 2'd3);
	wire [7:0]  tag_wa  = state == C_CLEAR ? clear_line : line;
	wire [12:0] tag_wd  = state == C_CLEAR ? 13'd0 : {1'b1, tag};

	always @(posedge clk) begin
		if (data_we)
			data[data_wa] <= f_rdata;
		if (tag_we)
			tags[tag_wa] <= tag_wd;
		data_q <= data[addr[11:2]];
		tag_q  <= tags[line];
	end

	wire hit = state == C_CHECK && tag_q == {1'b1, tag};

	always @(posedge clk) begin
		if (!resetn || invalidate) begin
			state      <= C_CLEAR;
			clear_line <= 8'd0;
		end else case (state)
			C_IDLE:
				if (valid && !is_write)
					state <= C_CHECK;           // tag and data arrive next cycle

			C_CHECK:
				if (!hit) begin
					state     <= C_FILL;
					fill_word <= 2'd0;
				end else
					state <= C_IDLE;

			C_FILL:
				if (f_ready) begin
					fill_word <= fill_word + 2'd1;
					if (fill_word == 2'd3)
						state <= C_IDLE;        // look again: now a hit
				end

			C_CLEAR: begin
				clear_line <= clear_line + 8'd1;
				if (clear_line == 8'd255)
					state <= C_IDLE;
			end
		endcase
	end

	assign ready   = valid && (is_write ? f_ready : hit);
	assign rdata   = data_q;

	assign f_valid = state == C_FILL || (valid && is_write);
	assign f_addr  = state == C_FILL ? {tag, line, fill_word, 2'b00} : addr;
	assign f_wstrb = state == C_FILL ? 4'd0 : wstrb;

endmodule
