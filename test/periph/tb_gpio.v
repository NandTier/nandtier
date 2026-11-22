// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_gpio: OUT/OE byte writes and read-back, pins driven only where OE
// is set, IN reading external levels, one-cycle bus answer.

`timescale 1 ns / 1 ps

module tb_gpio;

	reg clk = 0;
	always #20 clk = ~clk;
	reg resetn = 0;

	reg         valid = 0;
	reg  [31:0] addr, wdata;
	reg  [ 3:0] wstrb;
	wire        ready;
	wire [31:0] rdata;
	wire [6:0]  io;
	reg  [6:0]  ext;        // external drivers, z = not driven
	assign io = ext;

	nt_gpio #(.WIDTH(7)) dut (
		.clk(clk), .resetn(resetn),
		.valid(valid), .addr(addr), .wdata(wdata), .wstrb(wstrb),
		.ready(ready), .rdata(rdata), .io(io)
	);

	integer errors = 0;
	reg [31:0] r;

	task access(input [31:0] a, input [3:0] s, input [31:0] d, output [31:0] q);
		integer n;
		begin
			@(posedge clk);
			valid <= 1; addr <= a; wstrb <= s; wdata <= d;
			n = 0;
			@(posedge clk);
			while (!ready) begin @(posedge clk); n = n + 1; end
			if (n != 1) begin errors = errors + 1; $display("  access took %0d extra cycles", n); end
			q = rdata;
			valid <= 0;
		end
	endtask

	task check_eq(input [31:0] got, input [31:0] want, input [8*20-1:0] what);
		if (got !== want) begin
			errors = errors + 1;
			$display("  %0s: got %h, expected %h", what, got, want);
		end
	endtask

	initial begin
		ext = 7'bzzzzzzz;
		repeat (3) @(posedge clk);
		resetn <= 1;

		access(32'h8, 4'b0000, 0, r);
		check_eq(r, 0, "OE after reset");
		#1 check_eq(io, 7'bzzzzzzz, "pins after reset");

		access(32'h0, 4'b0001, 32'hFFFF_FF55, r);    // only byte 0 written
		access(32'h0, 4'b0000, 0, r);
		check_eq(r, 32'h0000_0055, "OUT byte write");
		access(32'h8, 4'b0001, 32'h0F, r);
		#1 check_eq(io, 7'bzzz0101, "pins with OE = 0x0F");

		ext = 7'b101zzzz;
		repeat (3) @(posedge clk);
		access(32'h4, 4'b0000, 0, r);
		check_eq(r, 32'b1010101, "IN");

		if (errors == 0)
			$display("PASS: nt_gpio");
		else
			$display("FAIL: nt_gpio: %0d errors", errors);
		$finish;
	end

endmodule
