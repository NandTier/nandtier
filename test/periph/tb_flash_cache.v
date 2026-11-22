// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_flash_cache in front of nt_spi_flash and sim/spi_flash_model.v:
// loops (hits), sequential runs, random reads, lines that evict each other,
// a flash mode change (invalidates), and new flash contents becoming
// visible after invalidation. Hits must answer one cycle after valid.

`timescale 1 ns / 1 ps

module tb_flash_cache;

	reg clk = 0;
	always #20 clk = ~clk;
	reg resetn = 0;

	reg         valid = 0;
	reg  [23:0] addr;
	wire        ready;
	wire [31:0] rdata;

	wire        f_valid, f_ready;
	wire [23:0] f_addr;
	wire [3:0]  f_wstrb;
	wire [31:0] f_rdata;

	reg         cfg_valid = 0;
	reg  [3:0]  cfg_wstrb;
	reg  [31:0] cfg_wdata;
	wire        cfg_ready, restart;
	wire [31:0] cfg_rdata;
	wire        csb, sck, io0_oe, io0_do, io1_oe, io1_do, io0, io1;

	nt_flash_cache dut (
		.clk(clk), .resetn(resetn), .invalidate(restart),
		.valid(valid), .addr(addr), .wstrb(4'd0), .ready(ready), .rdata(rdata),
		.f_valid(f_valid), .f_addr(f_addr), .f_wstrb(f_wstrb), .f_ready(f_ready), .f_rdata(f_rdata)
	);

	nt_spi_flash #(.POWERUP_CYCLES(250)) u_flash (
		.clk(clk), .resetn(resetn),
		.mem_valid(f_valid), .mem_addr(f_addr), .mem_wstrb(f_wstrb),
		.mem_ready(f_ready), .mem_rdata(f_rdata),
		.cfg_valid(cfg_valid), .cfg_wstrb(cfg_wstrb), .cfg_wdata(cfg_wdata),
		.cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata), .restart(restart),
		.flash_csb(csb), .flash_clk(sck),
		.io0_oe(io0_oe), .io0_do(io0_do), .io0_di(io0),
		.io1_oe(io1_oe), .io1_do(io1_do), .io1_di(io1)
	);

	assign io0 = io0_oe ? io0_do : 1'bz;
	assign io1 = io1_oe ? io1_do : 1'bz;
	pullup (io0);
	pullup (io1);

	spi_flash_model #(.SIZE(65536)) flash (.csb(csb), .sck(sck), .io0(io0), .io1(io1));

	integer errors = 0, i, n, cycles, hits = 0, slow_hits = 0;

	function [31:0] expected(input [23:0] a);
		expected = {flash.mem[a + 3], flash.mem[a + 2], flash.mem[a + 1], flash.mem[a]};
	endfunction

	task read(input [23:0] a, input expect_hit);
		begin
			@(posedge clk);
			valid <= 1;
			addr  <= a;
			cycles = 0;
			@(posedge clk) #1;
			while (!ready) begin
				@(posedge clk) #1;
				cycles = cycles + 1;
				if (cycles > 5000) begin $display("FAIL: read %06x hangs", a); $finish; end
			end
			if (rdata !== expected(a)) begin
				errors = errors + 1;
				if (errors < 10) $display("  read %06x: %08x, expected %08x", a, rdata, expected(a));
			end
			if (expect_hit) begin
				hits = hits + 1;
				if (cycles != 0) slow_hits = slow_hits + 1;
			end
			valid <= 0;
		end
	endtask

	task cfg_write(input [3:0] strb, input [31:0] d);
		begin
			@(posedge clk);
			cfg_valid <= 1; cfg_wstrb <= strb; cfg_wdata <= d;
			@(posedge clk);
			while (!cfg_ready) @(posedge clk);
			cfg_valid <= 0;
		end
	endtask

	initial begin
		for (i = 0; i < 65536; i = i + 1)
			flash.mem[i] = i * 13 + (i >> 8) * 7;
		repeat (3) @(posedge clk);
		resetn <= 1;

		// a 64-byte loop, run 10 times: misses once, then hits
		for (n = 0; n < 10; n = n + 1)
			for (i = 0; i < 16; i = i + 1)
				read(24'h0400 + i * 4, n > 0);

		cfg_write(4'b0100, 32'h0050_0000);      // dual + CRM: restarts, invalidates
		for (n = 0; n < 3; n = n + 1)
			for (i = 0; i < 16; i = i + 1)
				read(24'h0400 + i * 4, n > 0);

		// two lines 4 KiB apart share a cache line
		for (n = 0; n < 6; n = n + 1) begin
			read(24'h1000, 0);
			read(24'h2000, 0);
		end

		// random reads over 16 KiB
		for (i = 0; i < 400; i = i + 1)
			read(({$random} % 4096) * 4, 0);

		// change the flash under the cache: stale until invalidated
		read(24'h0404, 1);
		flash.mem[24'h0404] = 8'hA5;
		cfg_write(4'b0100, 32'h0040_0000);      // mode change: invalidates
		read(24'h0404, 0);

		if (errors == 0 && slow_hits == 0 && flash.errors == 0)
			$display("PASS: nt_flash_cache (%0d hits answered in one cycle)", hits);
		else
			$display("FAIL: nt_flash_cache: %0d data errors, %0d slow hits, %0d flash errors",
			         errors, slow_hits, flash.errors);
		$finish;
	end

endmodule
