// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_csr: counter addresses, reset, cycle and instret counting, carry
// into the high words.

`timescale 1 ns / 1 ps

module tb_csr;

	reg         clk = 0;
	reg         resetn = 0;
	reg         retire = 0;
	reg  [11:0] addr;
	wire [31:0] rdata;
	wire        valid;

	nt_csr dut (
		.clk(clk), .resetn(resetn), .retire(retire),
		.addr(addr), .rdata(rdata), .valid(valid)
	);

	integer errors = 0, checks = 0;
	integer i, retired;
	reg [63:0] exp_cycle;

	task tick;
		begin
			#4 clk = 1;
			#5 clk = 0;
			#1;
		end
	endtask

	task expect_csr(input [11:0] a, input [31:0] value);
		begin
			addr = a;
			#1;
			checks = checks + 1;
			if (!valid || rdata !== value) begin
				errors = errors + 1;
				$display("  csr %03x: got %08x (valid=%b), expected %08x", a, rdata, valid, value);
			end
		end
	endtask

	initial begin
		tick;
		resetn = 1;
		retired = 0;
		for (i = 0; i < 1000; i = i + 1) begin
			retire = $random;
			tick;
			retired = retired + retire;
		end
		retire = 0;
		exp_cycle = 1000;

		expect_csr(12'hC00, exp_cycle[31:0]);
		expect_csr(12'hC01, exp_cycle[31:0]);
		expect_csr(12'hC02, retired);
		expect_csr(12'hC80, 0);
		expect_csr(12'hC81, 0);
		expect_csr(12'hC82, 0);

		// every other address is invalid
		for (i = 0; i < 4096; i = i + 1) begin
			addr = i;
			#1;
			checks = checks + 1;
			if (valid !== (i == 12'hC00 || i == 12'hC01 || i == 12'hC02 ||
			               i == 12'hC80 || i == 12'hC81 || i == 12'hC82)) begin
				errors = errors + 1;
				$display("  csr %03x: valid=%b", i, valid);
			end
		end

		// carry into the high word
		dut.cycle   = 64'h0000_0000_ffff_fffe;
		dut.instret = 64'h0000_0000_ffff_ffff;
		retire = 1;
		tick;
		tick;
		expect_csr(12'hC00, 32'h0000_0000);
		expect_csr(12'hC80, 32'h0000_0001);
		expect_csr(12'hC02, 32'h0000_0001);
		expect_csr(12'hC82, 32'h0000_0001);

		// reset clears both
		resetn = 0;
		tick;
		expect_csr(12'hC00, 0);
		expect_csr(12'hC82, 0);

		if (errors == 0)
			$display("PASS: nt_csr (%0d checks)", checks);
		else
			$display("FAIL: nt_csr: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
