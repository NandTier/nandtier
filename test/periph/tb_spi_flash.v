// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_spi_flash against sim/spi_flash_model.v:
//   - XIP reads (sequential, random, repeated) in single, dual and
//     dual + continuous read mode, with mode changes in between
//   - bit-bang JEDEC ID read, sector erase and page program the way the
//     boot ROM does it, then reading the result back through XIP
// Also prints the cycles per sequential word in each mode.

`timescale 1 ns / 1 ps

module tb_spi_flash;

	reg clk = 0;
	always #20 clk = ~clk;      // 25 MHz
	reg resetn = 0;

	reg         mem_valid = 0, cfg_valid = 0;
	reg  [23:0] mem_addr;
	reg  [ 3:0] cfg_wstrb;
	reg  [31:0] cfg_wdata;
	wire        mem_ready, cfg_ready;
	wire [31:0] mem_rdata, cfg_rdata;
	wire        csb, sck, io0_oe, io0_do, io1_oe, io1_do;
	wire        io0, io1;

	nt_spi_flash #(.POWERUP_CYCLES(250)) dut (
		.clk(clk), .resetn(resetn),
		.mem_valid(mem_valid), .mem_addr(mem_addr), .mem_wstrb(4'd0),
		.mem_ready(mem_ready), .mem_rdata(mem_rdata),
		.cfg_valid(cfg_valid), .cfg_wstrb(cfg_wstrb), .cfg_wdata(cfg_wdata),
		.cfg_ready(cfg_ready), .cfg_rdata(cfg_rdata),
		.flash_csb(csb), .flash_clk(sck),
		.io0_oe(io0_oe), .io0_do(io0_do), .io0_di(io0),
		.io1_oe(io1_oe), .io1_do(io1_do), .io1_di(io1)
	);

	assign io0 = io0_oe ? io0_do : 1'bz;
	assign io1 = io1_oe ? io1_do : 1'bz;
	pullup (io0);
	pullup (io1);

	spi_flash_model #(.SIZE(65536), .TRES1_NS(8000)) flash (
		.csb(csb), .sck(sck), .io0(io0), .io1(io1)
	);

	integer errors = 0, i, n;

	function [7:0] pattern(input integer a);
		pattern = (a * 37 + (a >> 8) * 11 + 5) & 8'hFF;
	endfunction

	function [31:0] expected(input [23:0] a);
		expected = {flash.mem[a + 3], flash.mem[a + 2], flash.mem[a + 1], flash.mem[a]};
	endfunction

	task read_word(input [23:0] a, output integer cycles);
		begin
			@(posedge clk);
			mem_valid <= 1;
			mem_addr  <= a;
			cycles = 0;
			@(posedge clk);
			while (!mem_ready) begin
				@(posedge clk);
				cycles = cycles + 1;
				if (cycles > 2000) begin
					$display("FAIL: read of %06x hangs", a);
					$finish;
				end
			end
			if (mem_rdata !== expected(a)) begin
				errors = errors + 1;
				if (errors < 10)
					$display("  read %06x: got %08x, expected %08x (cfg %08x)", a, mem_rdata, expected(a), cfg_rdata);
			end
			mem_valid <= 0;
		end
	endtask

	task cfg_write(input [3:0] strb, input [31:0] data);
		begin
			@(posedge clk);
			cfg_valid <= 1;
			cfg_wstrb <= strb;
			cfg_wdata <= data;
			@(posedge clk);
			while (!cfg_ready) @(posedge clk);
			cfg_valid <= 0;
		end
	endtask

	task cfg_read(output [31:0] data);
		begin
			@(posedge clk);
			cfg_valid <= 1;
			cfg_wstrb <= 0;
			@(posedge clk);
			while (!cfg_ready) @(posedge clk);
			data = cfg_rdata;
			cfg_valid <= 0;
		end
	endtask

	// --- bit-bang SPI, as fw-brom does it -------------------------------------

	// register byte 0: bit 5 CSB, bit 4 CLK, bit 0 IO0; byte 1: bit 0 OE of IO0
	task bb(input csb_v, input clk_v, input mosi);
		cfg_write(4'b0001, {26'd0, csb_v, clk_v, 3'd0, mosi});
	endtask

	task bb_byte(input [7:0] tx, output [7:0] rx);
		integer b;
		reg [31:0] r;
		begin
			for (b = 7; b >= 0; b = b - 1) begin
				bb(0, 0, tx[b]);
				bb(0, 1, tx[b]);
				cfg_read(r);
				rx[b] = r[1];
			end
			bb(0, 0, 0);
		end
	endtask

	task bb_begin;
		begin
			cfg_write(4'b0011, 32'h0000_0120);   // OE IO0, CSB high
			cfg_write(4'b1000, 32'h0000_0000);   // XIP off
		end
	endtask

	task bb_end;
		cfg_write(4'b1000, 32'h8000_0000);       // XIP on (re-initialises)
	endtask

	task bb_wait_ready;
		reg [7:0] st, dummy;
		begin
			st = 8'h01;
			while (st[0]) begin
				bb(1, 0, 0);
				bb(0, 0, 0);
				bb_byte(8'h05, dummy);
				bb_byte(8'h00, st);
			end
			bb(1, 0, 0);
		end
	endtask

	// --- sequences ---------------------------------------------------------------

	task run_reads(input [8*16-1:0] name);
		integer c, total, words;
		reg [23:0] a;
		begin
			// sequential: measure the steady-state cost per word
			total = 0;
			for (i = 0; i < 64; i = i + 1) begin
				read_word(24'h000100 + i * 4, c);
				if (i >= 8) total = total + c;
			end
			$display("  %0s: %0d cycles per sequential word", name, total / 56);

			// random, repeated and short runs
			for (i = 0; i < 150; i = i + 1) begin
				a = ({$random} % 16000) * 4;
				read_word(a, c);
				if (i % 3 == 0) read_word(a, c);
				if (i % 5 == 0) begin
					read_word(a + 4, c);
					read_word(a + 8, c);
				end
			end
		end
	endtask

	reg [7:0] id0, id1, id2, dummy;
	integer   c;

	initial begin
		for (i = 0; i < 65536; i = i + 1)
			flash.mem[i] = pattern(i);

		repeat (5) @(posedge clk);
		resetn <= 1;

		run_reads("single");

		cfg_write(4'b0100, 32'h0040_0000);       // DUAL
		run_reads("dual");

		cfg_write(4'b0100, 32'h0050_0000);       // DUAL + CRM
		run_reads("dual+crm");

		cfg_write(4'b0100, 32'h0040_0000);       // back to DUAL (leaves CRM)
		for (i = 0; i < 20; i = i + 1) read_word(i * 4, c);
		cfg_write(4'b0100, 32'h0000_0000);       // single
		for (i = 0; i < 20; i = i + 1) read_word(24'h8000 + i * 4, c);
		cfg_write(4'b0100, 32'h0050_0000);       // CRM again
		for (i = 0; i < 20; i = i + 1) read_word(24'h4000 + i * 4, c);

		// JEDEC ID, erase sector 0x2000, program 16 bytes at 0x2010
		bb_begin;
		bb(1, 0, 0);
		bb(0, 0, 0);
		bb_byte(8'h9F, dummy);
		bb_byte(8'h00, id0);
		bb_byte(8'h00, id1);
		bb_byte(8'h00, id2);
		bb(1, 0, 0);
		if ({id0, id1, id2} !== 24'h856016) begin
			errors = errors + 1;
			$display("  JEDEC ID: got %02x %02x %02x", id0, id1, id2);
		end

		bb(0, 0, 0); bb_byte(8'h06, dummy); bb(1, 0, 0);
		bb(0, 0, 0); bb_byte(8'h20, dummy); bb_byte(8'h00, dummy); bb_byte(8'h20, dummy);
		bb_byte(8'h00, dummy); bb(1, 0, 0);
		bb_wait_ready;

		bb(0, 0, 0); bb_byte(8'h06, dummy); bb(1, 0, 0);
		bb(0, 0, 0); bb_byte(8'h02, dummy); bb_byte(8'h00, dummy); bb_byte(8'h20, dummy);
		bb_byte(8'h10, dummy);
		for (n = 0; n < 16; n = n + 1)
			bb_byte(8'hA0 + n, dummy);
		bb(1, 0, 0);
		bb_wait_ready;
		bb_end;

		for (n = 0; n < 4096; n = n + 1) begin
			if (flash.mem[16'h2000 + n] !== (n >= 16 && n < 32 ? 8'hA0 + n - 16 : 8'hFF)) begin
				errors = errors + 1;
				if (errors < 10) $display("  flash byte %04x = %02x after erase/program", 16'h2000 + n, flash.mem[16'h2000 + n]);
			end
		end
		for (i = 0; i < 16; i = i + 1)
			read_word(24'h2000 + i * 4, c);

		if (errors == 0 && flash.errors == 0)
			$display("PASS: nt_spi_flash");
		else
			$display("FAIL: nt_spi_flash: %0d data errors, %0d flash protocol errors", errors, flash.errors);
		$finish;
	end

	initial begin
		#20_000_000;
		$display("FAIL: nt_spi_flash: timeout");
		$finish;
	end

endmodule
