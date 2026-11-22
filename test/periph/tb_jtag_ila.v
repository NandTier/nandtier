// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Exercise the asynchronous JTAG user-chain bridge and register protocol.

`timescale 1 ns / 1 ps

module tb_jtag_ila;
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

	wire        ila_valid;
	wire [ 7:0] ila_addr;
	wire [31:0] ila_wdata;
	wire [ 3:0] ila_wstrb;
	wire        ila_ready = ila_valid;
	reg  [31:0] regs [0:7];
	wire [31:0] ila_rdata = regs[ila_addr[4:2]];
	wire        cpu_valid;
	wire [ 7:0] cpu_addr;
	wire [31:0] cpu_wdata;
	wire [ 3:0] cpu_wstrb;
	wire        cpu_ready = cpu_valid;
	reg  [31:0] cpu_reg;
	wire [31:0] cpu_rdata = cpu_addr == 8'h84 ? cpu_reg : 32'd0;
	wire        cpu_error = cpu_addr != 8'h80 && cpu_addr != 8'h84;

	nt_jtag_ila_bridge dut (
		.clk_sys(clk_sys), .resetn_sys(resetn_sys),
		.jtag_clk(jtag_clk), .jtag_resetn(jtag_resetn),
		.jtag_tdi(jtag_tdi), .jtag_shift(jtag_shift),
		.jtag_update(jtag_update), .jtag_chain1(jtag_chain1),
		.jtag_tdo(jtag_tdo),
		.ila_valid(ila_valid), .ila_addr(ila_addr),
		.ila_wdata(ila_wdata), .ila_wstrb(ila_wstrb),
		.ila_ready(ila_ready), .ila_rdata(ila_rdata),
		.cpu_valid(cpu_valid), .cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata), .cpu_wstrb(cpu_wstrb),
		.cpu_ready(cpu_ready), .cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error)
	);

	integer errors = 0;
	integer i;
	reg [63:0] ignored_response, response;

	always @(posedge clk_sys) begin
		if (resetn_sys && ila_valid && |ila_wstrb)
			regs[ila_addr[4:2]] <= ila_wdata;
		if (resetn_sys && cpu_valid && |cpu_wstrb)
			cpu_reg <= cpu_wdata;
	end

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

	task wait_for_system;
		integer n;
		begin
			for (n = 0; n < 16; n = n + 1)
				jtag_tick();
		end
	endtask

	task send_command(input [63:0] frame, input [7:0] seq);
		begin
			scan(frame, ignored_response);
			wait_for_system();
			scan(64'd0, response);
			if (response[59:52] !== seq) begin
				errors = errors + 1;
				$display("  response sequence: got %02x, expected %02x",
				         response[59:52], seq);
			end
		end
	endtask

	initial begin
		for (i = 0; i < 8; i = i + 1)
			regs[i] = 0;
		cpu_reg = 0;
		repeat (3) @(negedge clk_sys);
		resetn_sys = 1;
		jtag_resetn = 1;
		#1 jtag_resetn = 0;
		#1 jtag_resetn = 1;

		send_command({4'h1, 8'h04, 8'h21, 12'd0, 32'h1234_5678}, 8'h21);
		if (response[63:60] !== 4'h0 || regs[1] !== 32'h1234_5678) begin
			errors = errors + 1;
			$display("  JTAG write did not update analyzer register");
		end

		send_command({4'h2, 8'h04, 8'h22, 12'd0, 32'd0}, 8'h22);
		if (response[63:60] !== 4'h0 || response[31:0] !== 32'h1234_5678) begin
			errors = errors + 1;
			$display("  JTAG read returned status/data %h", response);
		end

		send_command({4'h2, 8'h24, 8'h23, 12'd0, 32'd0}, 8'h23);
		if (response[63:60] !== 4'h2) begin
			errors = errors + 1;
			$display("  invalid address did not return an error");
		end

		send_command({4'h1, 8'h84, 8'h24, 12'd0, 32'hAABB_CCDD}, 8'h24);
		if (response[63:60] !== 4'h0 || cpu_reg !== 32'hAABB_CCDD) begin
			errors = errors + 1;
			$display("  JTAG write did not reach CPU debug register");
		end
		send_command({4'h2, 8'h84, 8'h25, 12'd0, 32'd0}, 8'h25);
		if (response[63:60] !== 4'h0 || response[31:0] !== 32'hAABB_CCDD) begin
			errors = errors + 1;
			$display("  CPU debug register read returned %h", response);
		end
		send_command({4'h2, 8'h88, 8'h26, 12'd0, 32'd0}, 8'h26);
		if (response[63:60] !== 4'h2) begin
			errors = errors + 1;
			$display("  CPU debug error was not forwarded");
		end

		if (errors == 0)
			$display("PASS: ECP5 JTAG ILA bridge");
		else
			$display("FAIL: ECP5 JTAG ILA bridge: %0d errors", errors);
		$finish;
	end
endmodule
