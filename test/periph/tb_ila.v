// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Exercise the memory-mapped on-chip logic analyzer and its circular capture.

`timescale 1 ns / 1 ps

module tb_ila;
	reg clk = 0;
	always #5 clk = ~clk;
	reg resetn = 0;

	reg         valid = 0;
	reg  [31:0] addr = 0, wdata = 0;
	reg  [ 3:0] wstrb = 0;
	wire        ready;
	wire [31:0] rdata;

	reg         dbg_valid = 0;
	reg  [ 7:0] dbg_addr = 0;
	reg  [31:0] dbg_wdata = 0;
	reg  [ 3:0] dbg_wstrb = 0;
	wire        dbg_ready;
	wire [31:0] dbg_rdata;

	reg         bus_valid = 0, bus_ready = 0;
	reg  [31:0] bus_addr = 0, bus_wdata = 0, bus_rdata = 0;
	reg  [ 3:0] bus_wstrb = 0;
	reg         bus_instr = 0, bus_trap = 0;

	nt_ila dut (
		.clk(clk), .resetn(resetn),
		.valid(valid), .addr(addr), .wdata(wdata), .wstrb(wstrb),
		.ready(ready), .rdata(rdata),
		.dbg_valid(dbg_valid), .dbg_addr(dbg_addr), .dbg_wdata(dbg_wdata),
		.dbg_wstrb(dbg_wstrb), .dbg_ready(dbg_ready), .dbg_rdata(dbg_rdata),
		.bus_valid(bus_valid), .bus_ready(bus_ready), .bus_addr(bus_addr),
		.bus_wdata(bus_wdata), .bus_wstrb(bus_wstrb), .bus_rdata(bus_rdata),
		.bus_instr(bus_instr), .bus_trap(bus_trap)
	);

	integer errors = 0;
	integer i;
	reg [31:0] r;

	task write_reg(input [7:0] offset, input [31:0] value);
		begin
			@(negedge clk);
			valid = 1;
			addr = offset;
			wdata = value;
			wstrb = 4'hF;
			@(posedge clk);
			#1;
			valid = 0;
			wstrb = 0;
		end
	endtask

	task read_reg(input [7:0] offset, output [31:0] value);
		begin
			@(negedge clk);
			valid = 1;
			addr = offset;
			wstrb = 0;
			while (!ready) @(negedge clk);
			#1 value = rdata;
			@(posedge clk);
			#1 valid = 0;
		end
	endtask

	task sample(input [31:0] a, input [31:0] wd, input [31:0] rd,
	            input [3:0] ws, input v, input ready_i,
	            input instr_i, input trap_i);
		begin
			@(negedge clk);
			bus_addr = a;
			bus_wdata = wd;
			bus_rdata = rd;
			bus_wstrb = ws;
			bus_valid = v;
			bus_ready = ready_i;
			bus_instr = instr_i;
			bus_trap = trap_i;
			@(posedge clk);
			#1;
		end
	endtask

	task check_eq(input [31:0] got, input [31:0] want, input [8*24-1:0] what);
		if (got !== want) begin
			errors = errors + 1;
			$display("  %0s: got %h, expected %h", what, got, want);
		end
	endtask

	initial begin
		repeat (3) @(negedge clk);
		resetn = 1;

		write_reg(8'h04, 32'hDEAD_0000);
		write_reg(8'h08, 32'hFFFF_FFFF);
		write_reg(8'h0C, 32'd2);
		write_reg(8'h00, 32'h3);

		for (i = 0; i < 130; i = i + 1)
			sample(i, ~i, i + 1000, 4'h0, 1'b1, 1'b1, 1'b0, 1'b0);

		sample(32'hDEAD_0000, 32'hCAFE_BABE, 32'h1234_5678,
		       4'hF, 1'b1, 1'b1, 1'b0, 1'b0);
		sample(32'd131, ~32'd131, 32'd1131, 4'h0, 1'b1, 1'b1, 1'b1, 1'b0);
		sample(32'd132, ~32'd132, 32'd1132, 4'h0, 1'b1, 1'b1, 1'b0, 1'b1);

		read_reg(8'h00, r);
		check_eq(r, 32'h0000_8006, "triggered capture status");

		write_reg(8'h10, 32'd0);
		read_reg(8'h14, r);
		check_eq(r, 32'd5, "oldest sample address");
		read_reg(8'h18, r);
		check_eq(r, 32'd1005, "oldest sample data");
		read_reg(8'h1C, r);
		check_eq(r, 32'd3, "oldest sample flags");

		write_reg(8'h10, 32'd125);
		read_reg(8'h14, r);
		check_eq(r, 32'hDEAD_0000, "trigger sample address");
		read_reg(8'h1C, r);
		check_eq(r, 32'h0000_003F, "trigger sample flags");
		read_reg(8'h18, r);
		check_eq(r, 32'hCAFE_BABE, "trigger sample write data");

		write_reg(8'h10, 32'd127);
		read_reg(8'h14, r);
		check_eq(r, 32'd132, "newest sample address");
		read_reg(8'h18, r);
		check_eq(r, 32'd1132, "newest sample read data");
		read_reg(8'h1C, r);
		check_eq(r, 32'h0000_0083, "newest sample flags");

		write_reg(8'h00, 32'h1);
		for (i = 0; i < 128; i = i + 1)
			sample(i, i, i, 4'h0, 1'b1, 1'b1, 1'b0, 1'b0);
		read_reg(8'h00, r);
		check_eq(r, 32'h0000_8002, "automatic full-buffer stop");

		write_reg(8'h0C, 32'd0);
		write_reg(8'h00, 32'h3);
		sample(32'hDEAD_0000, 32'd0, 32'd0, 4'h0, 1'b1, 1'b0, 1'b0, 1'b0);
		read_reg(8'h00, r);
		check_eq(r & 32'd7, 32'd1, "trigger waits for bus acceptance");
		sample(32'hDEAD_0000, 32'd0, 32'd0, 4'h0, 1'b1, 1'b1, 1'b0, 1'b0);
		read_reg(8'h00, r);
		check_eq(r & 32'd7, 32'd6, "trigger captures accepted transfer");

		@(negedge clk);
		dbg_valid = 1;
		dbg_addr = 8'h04;
		dbg_wdata = 32'h1234_5678;
		dbg_wstrb = 4'hF;
		@(posedge clk);
		#1;
		dbg_valid = 0;
		dbg_wstrb = 0;
		read_reg(8'h04, r);
		check_eq(r, 32'h1234_5678, "debug-port register write");

		@(negedge clk);
		dbg_valid = 1;
		dbg_addr = 8'h04;
		#1 r = dbg_rdata;
		check_eq(r, 32'h1234_5678, "debug-port register read");
		@(posedge clk);
		#1 dbg_valid = 0;

		if (errors == 0)
			$display("PASS: nt_ila");
		else
			$display("FAIL: nt_ila: %0d errors", errors);
		$finish;
	end

endmodule
