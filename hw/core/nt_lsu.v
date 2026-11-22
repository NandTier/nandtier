// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier load/store unit (memory stage).
//
// Turns the byte address from the execute stage into a word-aligned bus
// request (store data replicated across the byte lanes, write strobes
// for the addressed bytes), and extracts and extends the addressed
// bytes of the read word into load_data when the bus access completes.
//
// funct3 is the LOAD/STORE funct3: bits [1:0] give the size
// (byte/half/word), bit 2 selects zero-extension for loads.

`timescale 1 ns / 1 ps

module nt_lsu (
	input             clk,

	input      [ 2:0] funct3,
	input             is_store,
	input      [31:0] addr,
	input      [31:0] store_data,
	output            misaligned,

	output     [31:0] bus_addr,
	output reg [31:0] bus_wdata,
	output     [ 3:0] bus_wstrb,

	input             load_we,
	input      [31:0] bus_rdata,
	output reg [31:0] load_data
);
	wire [1:0] size = funct3[1:0];
	wire [1:0] ofs  = addr[1:0];

	assign misaligned = (size == 2'b01 && ofs[0]) || (size == 2'b10 && ofs != 2'b00);

	assign bus_addr = {addr[31:2], 2'b00};

	reg [3:0] mask;
	always @* begin
		case (size)
			2'b00: begin
				bus_wdata = {4{store_data[7:0]}};
				mask      = 4'b0001 << ofs;
			end
			2'b01: begin
				bus_wdata = {2{store_data[15:0]}};
				mask      = ofs[1] ? 4'b1100 : 4'b0011;
			end
			default: begin
				bus_wdata = store_data;
				mask      = 4'b1111;
			end
		endcase
	end

	assign bus_wstrb = is_store ? mask : 4'b0000;

	wire [31:0] shifted = bus_rdata >> {ofs, 3'b000};
	wire        sext    = !funct3[2];

	always @(posedge clk) begin
		if (load_we) begin
			case (size)
				2'b00:   load_data <= {{24{sext && shifted[ 7]}}, shifted[ 7:0]};
				2'b01:   load_data <= {{16{sext && shifted[15]}}, shifted[15:0]};
				default: load_data <= bus_rdata;
			endcase
		end
	end

endmodule
