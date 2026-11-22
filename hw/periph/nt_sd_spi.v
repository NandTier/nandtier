// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier SD card SPI port: byte transfers in SPI mode 0, plus direct
// control of the pins for anything the byte engine does not cover.
//
// Registers:
//   +0x0 TX    write: start sending this byte (ignored while busy);
//              read: 0
//   +0x4 RX    the byte received by the last transfer (read only)
//   +0x8 CTRL  bit 0 SCK, bit 1 MOSI, bit 2 CS: pin levels while no
//              transfer runs (read/write);
//              bit 3 MISO pin, bit 4 busy (read only)
//   +0xC DIV   SCK half period in clock cycles, 1..255 (reset: DEFAULT_DIV)
//
// The bus answers in the same cycle.

`timescale 1 ns / 1 ps

module nt_sd_spi #(
	parameter [7:0] DEFAULT_DIV = 8'd6     // about 2 MHz at 25 MHz
) (
	input             clk,
	input             resetn,

	input             valid,
	input      [31:0] addr,
	input      [31:0] wdata,
	input      [ 3:0] wstrb,
	output            ready,
	output     [31:0] rdata,

	output            sd_sck,
	output            sd_mosi,
	output            sd_cs,
	input             sd_miso
);
	reg  [7:0] div;
	reg        man_sck, man_mosi, man_cs;

	reg  [7:0] tx_shift, rx_byte;
	reg  [3:0] bits_left;
	reg  [7:0] phase_count;
	reg        sck;

	wire busy = bits_left != 4'd0;
	wire wr   = valid && wstrb[0];

	always @(posedge clk) begin
		if (!resetn) begin
			div       <= DEFAULT_DIV;
			man_sck   <= 1'b0;
			man_mosi  <= 1'b1;
			man_cs    <= 1'b1;
			bits_left <= 4'd0;
			sck       <= 1'b0;
		end else begin
			if (wr && addr[3:2] == 2'd2 && !busy)
				{man_cs, man_mosi, man_sck} <= wdata[2:0];
			if (wr && addr[3:2] == 2'd3)
				div <= wdata[7:0] == 8'd0 ? 8'd1 : wdata[7:0];

			if (wr && addr[3:2] == 2'd0 && !busy) begin
				tx_shift    <= wdata[7:0];
				bits_left   <= 4'd8;
				phase_count <= div;
				sck         <= 1'b0;
			end else if (busy) begin
				if (phase_count != 8'd1) begin
					phase_count <= phase_count - 8'd1;
				end else begin
					phase_count <= div;
					sck <= !sck;
					if (!sck) begin
						rx_byte <= {rx_byte[6:0], sd_miso};    // rising edge: sample
					end else begin
						tx_shift  <= {tx_shift[6:0], 1'b1};   // falling edge: next bit
						bits_left <= bits_left - 4'd1;
					end
				end
			end
		end
	end

	assign sd_sck  = busy ? sck : man_sck;
	assign sd_mosi = busy ? tx_shift[7] : man_mosi;
	assign sd_cs   = man_cs;

	assign ready = valid;
	assign rdata = addr[3:2] == 2'd1 ? {24'd0, rx_byte} :
	               addr[3:2] == 2'd2 ? {27'd0, busy, sd_miso, man_cs, man_mosi, man_sck} :
	               addr[3:2] == 2'd3 ? {24'd0, div} :
	                                   32'd0;

endmodule
