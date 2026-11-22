// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Exercise CPU halt, single-step and register access through the ECP5
// user-chain command bridge.

`timescale 1 ns / 1 ps

module tb_cpu_debug;
	reg clk_sys = 0;
	always #5 clk_sys = ~clk_sys;
	reg resetn_sys = 0;

	reg jtag_clk = 0;
	reg jtag_resetn = 0;
	reg jtag_tdi = 0;
	reg jtag_shift = 0;
	reg jtag_update = 0;
	reg jtag_chain1 = 0;
	wire jtag_tdo;

	wire        cpu_valid;
	wire [ 7:0] cpu_addr;
	wire [31:0] cpu_wdata, cpu_rdata;
	wire [ 3:0] cpu_wstrb;
	wire        cpu_ready, cpu_error;
	wire        system_reset;
	wire        cpu_halted, cpu_trap;
	wire [31:0] cpu_pc, cpu_reg_rdata;
	wire        halt_request, resume, step;
	wire        pc_we, reg_we;
	wire [31:0] pc_wdata, reg_wdata;
	wire [ 4:0] reg_addr;

	wire        mem_valid, mem_instr;
	wire [31:0] mem_addr, mem_wdata;
	wire [ 3:0] mem_wstrb;
	wire [31:0] mem_rdata;
	wire        mem_ready = mem_valid;
	reg [31:0] rom [0:3];
	assign mem_rdata = rom[mem_addr[3:2]];

	nt_cpu_debug u_debug (
		.clk(clk_sys), .resetn(resetn_sys),
		.valid(cpu_valid), .addr(cpu_addr), .wdata(cpu_wdata),
		.wstrb(cpu_wstrb), .ready(cpu_ready), .rdata(cpu_rdata),
		.error(cpu_error), .core_halted(cpu_halted), .core_trap(cpu_trap),
		.core_pc(cpu_pc), .core_reg_rdata(cpu_reg_rdata),
		.core_halt_request(halt_request), .core_resume(resume),
		.core_step(step), .core_pc_we(pc_we), .core_pc_wdata(pc_wdata),
		.core_reg_addr(reg_addr), .core_reg_we(reg_we),
		.core_reg_wdata(reg_wdata), .system_reset(system_reset)
	);

	nandtier_core #(
		.PROGADDR_RESET(32'h8000_0000),
		.ENABLE_CPU_DEBUG(1)
	) u_cpu (
		.clk(clk_sys), .resetn(resetn_sys && !system_reset),
		.debug_halt_request(halt_request), .debug_resume(resume),
		.debug_step(step), .debug_pc_we(pc_we), .debug_pc_wdata(pc_wdata),
		.debug_reg_addr(reg_addr), .debug_reg_we(reg_we),
		.debug_reg_wdata(reg_wdata), .trap(cpu_trap),
		.debug_halted(cpu_halted), .debug_pc(cpu_pc),
		.debug_reg_rdata(cpu_reg_rdata),
		.mem_valid(mem_valid), .mem_instr(mem_instr),
		.mem_ready(mem_ready), .mem_addr(mem_addr),
		.mem_wdata(mem_wdata), .mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata)
	);

	wire ila_valid, ila_ready;
	assign ila_ready = 1'b0;
	wire [7:0] ila_addr;
	wire [31:0] ila_wdata;
	wire [3:0] ila_wstrb;
	nt_jtag_ila_bridge u_bridge (
		.clk_sys(clk_sys), .resetn_sys(resetn_sys),
		.jtag_clk(jtag_clk), .jtag_resetn(jtag_resetn),
		.jtag_tdi(jtag_tdi), .jtag_shift(jtag_shift),
		.jtag_update(jtag_update), .jtag_chain1(jtag_chain1),
		.jtag_tdo(jtag_tdo),
		.ila_valid(ila_valid), .ila_addr(ila_addr),
		.ila_wdata(ila_wdata), .ila_wstrb(ila_wstrb),
		.ila_ready(ila_ready), .ila_rdata(32'd0),
		.cpu_valid(cpu_valid), .cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
		.cpu_ready(cpu_ready), .cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error)
	);

	integer errors = 0;
	integer i, poll;
	reg [7:0] seqno = 0;
	reg [63:0] ignored_response, response;

	task jtag_tick;
		begin
			#50 jtag_clk = 1;
			#50 jtag_clk = 0;
		end
	endtask

	task scan(input [63:0] frame, output [63:0] result);
		begin
			jtag_chain1 = 1;
			jtag_shift = 0;
			jtag_update = 0;
			jtag_tick();
			result[0] = jtag_tdo;
			jtag_shift = 1;
			for (i = 0; i < 64; i = i + 1) begin
				jtag_tdi = frame[i];
				jtag_tick();
				if (i < 63)
					result[i+1] = jtag_tdo;
			end
			jtag_shift = 0;
			jtag_update = 1;
			jtag_tick();
			jtag_update = 0;
			jtag_chain1 = 0;
		end
	endtask

	task transfer(input [3:0] op, input [7:0] addr,
	              input [31:0] data, output [31:0] result);
		reg [63:0] request;
		begin
			seqno = seqno + 1'b1;
			request = {op, addr, seqno, 12'd0, data};
			scan(request, ignored_response);
			repeat (16) jtag_tick();
			scan(64'd0, response);
			if (response[59:52] !== seqno ||
			    response[63:60] !== 4'h0) begin
				errors = errors + 1;
				$display("  command %x @ %02x returned %h",
				         op, addr, response);
			end
			result = response[31:0];
		end
	endtask

	task write_reg(input [7:0] addr, input [31:0] value);
		reg [31:0] ignored;
		begin
			transfer(4'h1, addr, value, ignored);
		end
	endtask

	task read_reg(input [7:0] addr, output [31:0] value);
		begin
			transfer(4'h2, addr, 32'd0, value);
		end
	endtask

	task expect_write_error(input [7:0] addr, input [31:0] data);
		reg [63:0] request;
		begin
			seqno = seqno + 1'b1;
			request = {4'h1, addr, seqno, 12'd0, data};
			scan(request, ignored_response);
			repeat (16) jtag_tick();
			scan(64'd0, response);
			if (response[59:52] !== seqno || response[63:60] !== 4'h2) begin
				errors = errors + 1;
				$display("  expected rejected write at %02x, got %h",
				         addr, response);
			end
		end
	endtask

	task wait_halted;
		reg [31:0] status;
		begin
			status = 0;
			for (poll = 0; poll < 32 && !status[0]; poll = poll + 1)
				read_reg(8'h80, status);
			if (!status[0]) begin
				errors = errors + 1;
				$display("  CPU did not halt; status=%08x", status);
			end
		end
	endtask

	task check_value(input [31:0] got, input [31:0] expected,
	                 input [160*8-1:0] label);
		begin
			if (got !== expected) begin
				errors = errors + 1;
				$display("  %0s: got %08x, expected %08x",
				         label, got, expected);
			end
		end
	endtask

	reg [31:0] value;
	initial begin
		rom[0] = 32'h0010_0093; // addi x1, x0, 1
		rom[1] = 32'h0010_8093; // addi x1, x1, 1
		rom[2] = 32'h0000_006f; // jal x0, 0
		rom[3] = 32'h0000_0013; // nop

		repeat (4) @(negedge clk_sys);
		resetn_sys = 1;
		jtag_resetn = 1;
		repeat (2) @(negedge clk_sys);
		jtag_resetn = 0;
		#1 jtag_resetn = 1;

		write_reg(8'h80, 32'h1);
		wait_halted();
		write_reg(8'h84, 32'h8000_0000);
		write_reg(8'h88, 32'd1);
		write_reg(8'h8C, 32'd0);

		write_reg(8'h80, 32'h4);
		wait_halted();
		read_reg(8'h84, value);
		check_value(value, 32'h8000_0004, "PC after first step");
		read_reg(8'h8C, value);
		check_value(value, 32'd1, "x1 after first step");

		write_reg(8'h80, 32'h4);
		wait_halted();
		read_reg(8'h84, value);
		check_value(value, 32'h8000_0008, "PC after second step");
		read_reg(8'h8C, value);
		check_value(value, 32'd2, "x1 after second step");

		write_reg(8'h80, 32'h2);
		repeat (40) @(posedge clk_sys);
		if (cpu_halted) begin
			errors = errors + 1;
			$display("  CPU did not resume");
		end
		expect_write_error(8'h84, 32'h8000_0000);
		write_reg(8'h80, 32'h1);
		wait_halted();

		write_reg(8'h90, 32'h1);
		if (!system_reset) begin
			errors = errors + 1;
			$display("  system reset did not assert");
		end
		read_reg(8'h84, value);
		check_value(value, 32'h8000_0000, "PC during system reset");
		write_reg(8'h90, 32'h0);
		if (system_reset) begin
			errors = errors + 1;
			$display("  system reset did not release");
		end

		if (errors == 0)
			$display("PASS: ECP5 JTAG CPU debug");
		else
			$display("FAIL: ECP5 JTAG CPU debug: %0d errors", errors);
		$finish;
	end

	initial begin
		#5_000_000;
		$display("FAIL: ECP5 JTAG CPU debug timed out");
		$finish;
	end
endmodule
