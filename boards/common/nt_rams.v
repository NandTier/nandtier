// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Portable versions of the RAMs hw/mem/nt_ram8k.v uses, for the
// open-source flows (oss/): plain Verilog that Yosys maps to the block RAMs
// of any FPGA. Same module names and ports as the Gowin IP in gowin_ip/ and
// project/src/gowin_sp/, which the Gowin IDE project uses instead:
//
//   bootram_2kx8_0-3  2048 x 8, byte lane n of the boot ROM, read from
//                     fw-brom_<n>.hex (fw/fw-brom/build, copied next to the
//                     synthesis run by oss/Makefile) at synthesis, so the
//                     bitstream always has the current boot ROM
//   sram_2kx8         2048 x 8
//
// They behave like the Gowin SP block RAMs (READ_MODE 0, WRITE_MODE
// "normal"): with ce, a write stores din, a read puts the word on dout one
// clock later; dout holds otherwise, including during writes.

`timescale 1 ns / 1 ps

// 2048 x 8 single-port block RAM, optionally initialised from a hex file
module nt_bram_2kx8 #(
	parameter INIT_FILE = ""
) (
	output reg [7:0] dout,
	input            clk,
	input            ce,
	input            wre,
	input     [10:0] ad,
	input      [7:0] din
);
	reg [7:0] mem [0:2047];

	initial begin
		dout = 8'd0;
		if (INIT_FILE != "")
			$readmemh(INIT_FILE, mem);
	end

	always @(posedge clk)
		if (ce) begin
			if (wre)
				mem[ad] <= din;
			else
				dout <= mem[ad];
		end
endmodule

// Wrappers with the Gowin IP's ports. oce and reset are not needed: the bus
// takes dout in the cycle after ce (see hw/mem/nt_ram8k.v).
`define NT_BRAM_WRAPPER(name, file) \
	module name (output [7:0] dout, input clk, input oce, input ce, input reset, \
	             input wre, input [10:0] ad, input [7:0] din); \
		nt_bram_2kx8 #(.INIT_FILE(file)) u_ram (.dout(dout), .clk(clk), .ce(ce), .wre(wre), \
		                                        .ad(ad), .din(din)); \
	endmodule

`NT_BRAM_WRAPPER(bootram_2kx8_0, "fw-brom_0.hex")
`NT_BRAM_WRAPPER(bootram_2kx8_1, "fw-brom_1.hex")
`NT_BRAM_WRAPPER(bootram_2kx8_2, "fw-brom_2.hex")
`NT_BRAM_WRAPPER(bootram_2kx8_3, "fw-brom_3.hex")
`NT_BRAM_WRAPPER(sram_2kx8, "")
