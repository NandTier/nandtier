// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Memory model and bus checker for the core testbenches.
//
// Memory map seen by the program:
//   0x8000_0000 - 0x8000_FFFF  RAM (64 KB, preloaded from +hex=<file>)
//   0x1000_0000                TOHOST:  write 1 = PASS, anything else = FAIL code
//   0x1000_0004                CONSOLE: write a byte to print it
//
// Plusargs:
//   +hex=<file>   objcopy -O verilog image to load (required)
//   +lat=<n>      cycles from mem_valid to mem_ready (default 1, 0 = same cycle)
//   +rand_lat     random latency of 0..4 cycles per transfer
//   +trace        print every memory transaction
//   +storelog=<f> write every completed store to <f> as
//                 "address strobes data" (data of the strobed bytes only)
//
// The checker fails the simulation if the core breaks the bus protocol
// the SoC slaves rely on (see hw/core/nt_bus.v).

`timescale 1 ns / 1 ps

module tb_mem #(
	parameter NAME     = "mem",
	parameter VERBOSE  = 1,         // print console output and trace
	parameter RAM_BASE = 32'h8000_0000,
	parameter RAM_SIZE = 32'h0001_0000
) (
	input             clk,
	input             resetn,

	input             mem_valid,
	input             mem_instr,
	output            mem_ready,
	input      [31:0] mem_addr,
	input      [31:0] mem_wdata,
	input      [ 3:0] mem_wstrb,
	output     [31:0] mem_rdata,

	output reg        done,         // TOHOST was written
	output reg [31:0] done_code,

	output            store         // a write completes this cycle
);
	localparam TOHOST  = 32'h1000_0000;
	localparam CONSOLE = 32'h1000_0004;

	reg [7:0] ram [RAM_BASE : RAM_BASE + RAM_SIZE - 1];

	reg [1023:0] hexfile, logname;
	reg          trace, rand_lat;
	integer      lat, cur_lat, waited, i;
	integer      storelog = 0;

	initial begin
		for (i = RAM_BASE; i < RAM_BASE + RAM_SIZE; i = i + 1)
			ram[i] = 8'h00;
		if (!$value$plusargs("hex=%s", hexfile)) begin
			$display("FAIL: no +hex=<file> given");
			$finish;
		end
		$readmemh(hexfile, ram);
		if (!$value$plusargs("lat=%d", lat))
			lat = 1;
		rand_lat = $test$plusargs("rand_lat");
		if ($value$plusargs("storelog=%s", logname))
			storelog = $fopen(logname, "w");
		trace    = $test$plusargs("trace") && VERBOSE;
		cur_lat  = lat;
		waited   = 0;
		done     = 0;
	end

	wire in_ram = mem_addr >= RAM_BASE && mem_addr < RAM_BASE + RAM_SIZE;

	assign mem_ready = mem_valid && waited >= cur_lat;
	assign mem_rdata = in_ram ? {ram[mem_addr + 3], ram[mem_addr + 2], ram[mem_addr + 1], ram[mem_addr + 0]}
	                          : 32'hxxxx_xxxx;
	assign store     = mem_valid && mem_ready && |mem_wstrb;

	always @(posedge clk) begin
		if (mem_valid && !mem_ready)
			waited <= waited + 1;

		if (mem_valid && mem_ready) begin
			waited  <= 0;
			cur_lat <= rand_lat ? $urandom % 5 : lat;

			if (trace)
				$display("  %0s %s addr=%08x wstrb=%b wdata=%08x rdata=%08x", NAME,
				         mem_instr ? "I" : "D", mem_addr, mem_wstrb, mem_wdata, mem_rdata);

			if (storelog && |mem_wstrb)
				$fdisplay(storelog, "%08x %x %08x", mem_addr, mem_wstrb, mem_wdata &
				          {{8{mem_wstrb[3]}}, {8{mem_wstrb[2]}}, {8{mem_wstrb[1]}}, {8{mem_wstrb[0]}}});

			if (in_ram) begin
				if (mem_wstrb[0]) ram[mem_addr + 0] <= mem_wdata[ 7: 0];
				if (mem_wstrb[1]) ram[mem_addr + 1] <= mem_wdata[15: 8];
				if (mem_wstrb[2]) ram[mem_addr + 2] <= mem_wdata[23:16];
				if (mem_wstrb[3]) ram[mem_addr + 3] <= mem_wdata[31:24];
			end else if (mem_addr == CONSOLE && |mem_wstrb) begin
				if (VERBOSE) begin
					$write("%c", mem_wdata[7:0]);
					$fflush;
				end
			end else if (mem_addr == TOHOST && |mem_wstrb) begin
				done      <= 1;
				done_code <= mem_wdata;
			end else begin
				$display("FAIL: %0s: access to unmapped address %08x (instr=%b)", NAME, mem_addr, mem_instr);
				$finish;
			end
		end
	end

	// --- bus protocol checker ----------------------------------------------

	reg        prev_valid, prev_ready, prev_instr;
	reg [31:0] prev_addr, prev_wdata;
	reg [ 3:0] prev_wstrb;

	task protocol_fail(input [8*64-1:0] what);
		begin
			$display("FAIL: %0s: bus protocol violation: %0s (addr=%08x)", NAME, what, mem_addr);
			$finish;
		end
	endtask

	always @(posedge clk) begin
		prev_valid <= resetn && mem_valid;
		prev_ready <= mem_ready;
		prev_instr <= mem_instr;
		prev_addr  <= mem_addr;
		prev_wdata <= mem_wdata;
		prev_wstrb <= mem_wstrb;

		if (resetn && mem_valid) begin
			if (mem_addr[1:0] != 2'b00)
				protocol_fail("unaligned mem_addr");
			if (mem_instr && mem_wstrb != 4'b0000)
				protocol_fail("write strobes on an instruction fetch");
			if (prev_valid && prev_ready)
				protocol_fail("no idle cycle after a transfer");
			if (prev_valid && !prev_ready) begin
				if (mem_addr != prev_addr || mem_instr != prev_instr || mem_wstrb != prev_wstrb)
					protocol_fail("request changed while waiting for ready");
				if (|mem_wstrb && mem_wdata != prev_wdata)
					protocol_fail("write data changed while waiting for ready");
			end
		end else if (resetn && prev_valid && !prev_ready) begin
			protocol_fail("mem_valid dropped before mem_ready");
		end
	end

endmodule
