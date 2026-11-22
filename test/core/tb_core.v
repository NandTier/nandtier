// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Standalone testbench for nandtier_core.
//
// Memory map and memory plusargs: see tb_mem.v. Additionally:
//   +expect_trap    test passes when the core asserts trap

`timescale 1 ns / 1 ps

module tb_core;

	localparam TIMEOUT = 2_000_000;

	reg clk = 0;
	reg resetn = 0;
	always #5 clk = ~clk;

	wire        trap;
	wire        mem_valid;
	wire        mem_instr;
	wire        mem_ready;
	wire [31:0] mem_addr;
	wire [31:0] mem_wdata;
	wire [ 3:0] mem_wstrb;
	wire [31:0] mem_rdata;
	wire debug_halted, debug_pc_we, debug_reg_we;
	wire [31:0] debug_pc, debug_reg_rdata;
	wire        done;
	wire [31:0] done_code;

	// Same configuration as u_nandtier_core in hw/nandtier.v
	nandtier_core #(
		.PROGADDR_RESET(32'h8000_0000)
	) dut (
		.clk      (clk),
		.resetn   (resetn),
		.debug_halt_request(1'b0),
		.debug_resume(1'b0),
		.debug_step(1'b0),
		.debug_pc_we(1'b0),
		.debug_pc_wdata(32'd0),
		.debug_reg_addr(5'd0),
		.debug_reg_we(1'b0),
		.debug_reg_wdata(32'd0),
		.trap     (trap),
		.debug_halted(debug_halted),
		.debug_pc(debug_pc),
		.debug_reg_rdata(debug_reg_rdata),
		.mem_valid(mem_valid),
		.mem_instr(mem_instr),
		.mem_ready(mem_ready),
		.mem_addr (mem_addr),
		.mem_wdata(mem_wdata),
		.mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata)
	);

	tb_mem mem (
		.clk      (clk),
		.resetn   (resetn),
		.mem_valid(mem_valid),
		.mem_instr(mem_instr),
		.mem_ready(mem_ready),
		.mem_addr (mem_addr),
		.mem_wdata(mem_wdata),
		.mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata),
		.done     (done),
		.done_code(done_code),
		.store    ()
	);

	reg expect_trap;
	integer cycles = 0;

	initial begin
		expect_trap = $test$plusargs("expect_trap");
		repeat (10) @(posedge clk);
		resetn <= 1;
	end

	always @(posedge clk) begin
		cycles <= cycles + 1;

		if (done) begin
			if (expect_trap)
				$display("FAIL: program finished (code %0d) but a trap was expected", done_code);
			else if (done_code == 1)
				$display("PASS: %0s (%0d cycles)", mem.hexfile, cycles);
			else
				$display("FAIL: test #%0d failed (%0d cycles)", done_code >> 1, cycles);
			$finish;
		end

		if (resetn && trap) begin
			if (expect_trap)
				$display("PASS: %0s trapped as expected (%0d cycles)", mem.hexfile, cycles);
			else
				$display("FAIL: unexpected trap (%0d cycles)", cycles);
			$finish;
		end

		if (cycles == TIMEOUT) begin
			$display("FAIL: timeout after %0d cycles", TIMEOUT);
			$finish;
		end
	end

endmodule
