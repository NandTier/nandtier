// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_muldiv against the RISC-V M extension rules, computed here with
// 64-bit Verilog arithmetic: random operands and the corner cases (0, 1,
// -1, -2^31, division by zero, -2^31 / -1), all eight operations. Also
// checks the timing: multiplies done after one cycle, divides within 40.

`timescale 1 ns / 1 ps

module tb_muldiv;
	reg         clk = 0, resetn = 0, go = 0;
	reg  [ 2:0] funct3;
	reg  [31:0] a, b;
	wire        done;
	wire [31:0] y;

	nt_muldiv dut (.clk(clk), .resetn(resetn), .go(go), .funct3(funct3), .a(a), .b(b),
	               .done(done), .y(y));

	always #5 clk = !clk;

	function [31:0] golden(input [2:0] f, input [31:0] x, input [31:0] z);
		reg signed [63:0] sx, sz, sq;   // signed arithmetic kept apart from unsigned constants
		reg        [63:0] ux, uz, p;
		begin
			sx = $signed(x); sz = $signed(z);
			ux = {32'd0, x}; uz = {32'd0, z};
			case (f)
				3'd0: begin p = sx * sz; golden = p[31:0]; end
				3'd1: begin p = sx * sz; golden = p[63:32]; end
				3'd2: begin p = sx * $signed(uz); golden = p[63:32]; end
				3'd3: begin p = ux * uz; golden = p[63:32]; end
				3'd4: begin
					sq = sx / sz;
					golden = z == 0 ? 32'hFFFF_FFFF : (x == 32'h8000_0000 && z == 32'hFFFF_FFFF) ? 32'h8000_0000 : sq[31:0];
				end
				3'd5: golden = z == 0 ? 32'hFFFF_FFFF : x / z;
				3'd6: begin
					sq = sx % sz;
					golden = z == 0 ? x : (x == 32'h8000_0000 && z == 32'hFFFF_FFFF) ? 32'd0 : sq[31:0];
				end
				default: golden = z == 0 ? x : x % z;
			endcase
		end
	endfunction

	integer errors = 0, checks = 0, i, cyc;

	task run(input [2:0] f, input [31:0] x, input [31:0] z);
		reg [31:0] want;
		begin
			@(posedge clk) #1;
			funct3 = f; a = x; b = z; go = 1;
			cyc = 0;
			while (!done && cyc < 60) begin
				@(posedge clk) #1;
				cyc = cyc + 1;
			end
			want = golden(f, x, z);
			checks = checks + 1;
			if (!done || y !== want || (f < 4 && cyc != 1) || cyc > 40) begin
				if (errors < 10)
					$display("tb_muldiv: funct3 %0d a %h b %h: got %h after %0d cycles, want %h",
					         f, x, z, y, cyc, want);
				errors = errors + 1;
			end
			go = 0;
			@(posedge clk) #1;
			if (done) begin
				errors = errors + 1;
				$display("tb_muldiv: done stays up after go falls");
			end
		end
	endtask

	reg [31:0] corners [0:7];

	initial begin
		corners[0] = 0; corners[1] = 1; corners[2] = 32'hFFFF_FFFF; corners[3] = 32'h8000_0000;
		corners[4] = 32'h7FFF_FFFF; corners[5] = 2; corners[6] = 32'hFFFF_FFFE; corners[7] = 12345;
		#20 resetn = 1;
		for (i = 0; i < 8 * 8 * 8; i = i + 1)
			run(i % 8, corners[(i / 8) % 8], corners[i / 64]);
		for (i = 0; i < 6000; i = i + 1)
			run($random % 8, $random, i % 5 == 0 ? $random % 100 : $random);
		if (errors == 0)
			$display("PASS: nt_muldiv (%0d checks)", checks);
		else
			$display("FAIL: nt_muldiv: %0d of %0d checks failed", errors, checks);
		$finish;
	end
endmodule
