// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_uart with TX looped back to RX: byte values, bit timing, the bus
// waiting for a busy transmitter, receive FIFO order, overflow (extra
// bytes are dropped) and the empty value 0xFFFF_FFFF.

`timescale 1 ns / 1 ps

module tb_uart;

	reg clk = 0;
	always #20 clk = ~clk;
	reg resetn = 0;

	reg         valid = 0;
	reg  [31:0] addr, wdata;
	reg  [ 3:0] wstrb;
	wire        ready;
	wire [31:0] rdata;
	wire        line;

	nt_uart #(.DEFAULT_DIV(16'd20)) dut (
		.clk(clk), .resetn(resetn),
		.valid(valid), .addr(addr), .wdata(wdata), .wstrb(wstrb),
		.ready(ready), .rdata(rdata),
		.rx(line), .tx(line)
	);

	integer errors = 0, i, waited;
	reg [31:0] r;

	task access(input [31:0] a, input [3:0] s, input [31:0] d, output [31:0] q, output integer cycles);
		begin
			@(posedge clk);
			valid <= 1; addr <= a; wstrb <= s; wdata <= d;
			@(posedge clk);
			cycles = 0;
			while (!ready) begin
				@(posedge clk);
				cycles = cycles + 1;
			end
			q = rdata;
			valid <= 0;
		end
	endtask

	task check_eq(input [31:0] got, input [31:0] want, input [8*24-1:0] what);
		if (got !== want) begin
			errors = errors + 1;
			$display("  %0s: got %08x, expected %08x", what, got, want);
		end
	endtask

	// bit timing: the start bit lasts one bit period
	realtime t_start, t_bit;
	initial begin
		@(posedge resetn);
		@(negedge line) t_start = $realtime;
		@(posedge line) t_bit = $realtime - t_start;   // 0xA5: start bit, then LSB = 1
	end

	initial begin
		repeat (3) @(posedge clk);
		resetn <= 1;

		access(32'h4, 4'b0000, 0, r, waited);
		check_eq(r, 20, "reset divider");
		access(32'h0, 4'b0000, 0, r, waited);
		check_eq(r, 32'hFFFF_FFFF, "empty read");

		// one byte, check the frame length: 9.5 bit periods from start
		// edge to the middle of the stop bit
		access(32'h0, 4'b0001, 32'hA5, r, waited);
		repeat (20 * 11) @(posedge clk);
		access(32'h0, 4'b0000, 0, r, waited);
		check_eq(r, 32'hA5, "first byte");
		check_eq(t_bit, 20 * 40, "bit period (ns)");

		// 18 bytes back to back: the bus waits per byte, the FIFO keeps 16
		for (i = 0; i < 18; i = i + 1) begin
			access(32'h0, 4'b1111, 32'h30 + i, r, waited);
			if (i > 0 && waited < 20 * 9) begin
				errors = errors + 1;
				$display("  byte %0d: bus did not wait for the transmitter (%0d cycles)", i, waited);
			end
		end
		repeat (20 * 12) @(posedge clk);
		for (i = 0; i < 16; i = i + 1) begin
			access(32'h0, 4'b0000, 0, r, waited);
			check_eq(r, 32'h30 + i, "FIFO order");
		end
		access(32'h0, 4'b0000, 0, r, waited);
		check_eq(r, 32'hFFFF_FFFF, "overflow dropped");

		// all byte values at a different divider
		access(32'h4, 4'b0011, 7, r, waited);
		for (i = 0; i < 256; i = i + 1) begin
			access(32'h0, 4'b0001, i, r, waited);
			repeat (7 * 11) @(posedge clk);
			access(32'h0, 4'b0000, 0, r, waited);
			check_eq(r, i, "byte value");
		end

		if (errors == 0)
			$display("PASS: nt_uart");
		else
			$display("FAIL: nt_uart: %0d errors", errors);
		$finish;
	end

endmodule
