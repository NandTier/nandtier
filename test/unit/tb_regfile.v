// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_regfile: random writes against a shadow copy, both read ports,
// x0 ignores writes and reads as zero.

`timescale 1 ns / 1 ps

module tb_regfile;

	reg         clk = 0;
	reg  [ 4:0] raddr1, raddr2, waddr;
	reg  [ 4:0] debug_waddr = 0;
	reg  [31:0] wdata;
	reg         we;
	wire [31:0] rdata1, rdata2;

	nt_regfile dut (
		.clk(clk),
		.raddr1(raddr1), .rdata1(rdata1),
		.raddr2(raddr2), .rdata2(rdata2),
		.we(we), .waddr(waddr), .wdata(wdata),
		.debug_we(1'b0), .debug_waddr(debug_waddr),
		.debug_wdata(32'd0)
	);

	reg [31:0] shadow [0:31];
	integer errors = 0, checks = 0;
	integer i;

	task tick;
		begin
			#4 clk = 1;
			#5 clk = 0;
			#1;
		end
	endtask

	initial begin
		// fill every register, including an attempt on x0
		we = 1;
		for (i = 0; i < 32; i = i + 1) begin
			waddr = i;
			wdata = $random;
			shadow[i] = i == 0 ? 0 : wdata;
			tick;
		end

		for (i = 0; i < 20000; i = i + 1) begin
			we     = $random;
			waddr  = $random;
			wdata  = $random;
			raddr1 = $random;
			raddr2 = i % 5 == 0 ? raddr1 : $random;
			#1;
			checks = checks + 1;
			if (rdata1 !== shadow[raddr1] || rdata2 !== shadow[raddr2]) begin
				errors = errors + 1;
				if (errors <= 10)
					$display("  read x%0d=%08x x%0d=%08x, expected %08x %08x",
					         raddr1, rdata1, raddr2, rdata2, shadow[raddr1], shadow[raddr2]);
			end
			tick;
			if (we && waddr != 0)
				shadow[waddr] = wdata;
		end

		if (errors == 0)
			$display("PASS: nt_regfile (%0d checks)", checks);
		else
			$display("FAIL: nt_regfile: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
