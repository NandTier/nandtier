// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_alu: every operation on corner-case and random operands against
// plain Verilog operators.

`timescale 1 ns / 1 ps

module tb_alu;

	reg  [ 3:0] op;
	reg  [31:0] a, b;
	wire [31:0] y;

	nt_alu dut (.op(op), .a(a), .b(b), .y(y));

	localparam N_OPS = 10;
	reg [3:0] ops [0:N_OPS-1];
	initial begin
		ops[0] = 4'b0000; ops[1] = 4'b1000; ops[2] = 4'b0001; ops[3] = 4'b0010;
		ops[4] = 4'b0011; ops[5] = 4'b0100; ops[6] = 4'b0101; ops[7] = 4'b1101;
		ops[8] = 4'b0110; ops[9] = 4'b0111;
	end

	function [31:0] expected(input [3:0] op, input [31:0] a, input [31:0] b);
		case (op)
			4'b0000: expected = a + b;
			4'b1000: expected = a - b;
			4'b0001: expected = a << b[4:0];
			4'b0010: expected = $signed(a) < $signed(b) ? 1 : 0;
			4'b0011: expected = a < b ? 1 : 0;
			4'b0100: expected = a ^ b;
			4'b0101: expected = a >> b[4:0];
			4'b1101: expected = $signed(a) >>> b[4:0];
			4'b0110: expected = a | b;
			4'b0111: expected = a & b;
			default: expected = 32'hxxxx_xxxx;
		endcase
	endfunction

	localparam N_CORNER = 10;
	reg [31:0] corner [0:N_CORNER-1];
	initial begin
		corner[0] = 32'h0000_0000; corner[1] = 32'h0000_0001; corner[2] = 32'hffff_ffff;
		corner[3] = 32'h8000_0000; corner[4] = 32'h7fff_ffff; corner[5] = 32'h0000_001f;
		corner[6] = 32'h0000_0020; corner[7] = 32'h8000_0001; corner[8] = 32'hffff_ffe0;
		corner[9] = 32'h5555_aaaa;
	end

	integer errors = 0, checks = 0;
	integer i, j, k;

	task check;
		begin
			#1;
			checks = checks + 1;
			if (y !== expected(op, a, b)) begin
				errors = errors + 1;
				if (errors <= 10)
					$display("  op=%b a=%08x b=%08x: got %08x, expected %08x", op, a, b, y, expected(op, a, b));
			end
		end
	endtask

	initial begin
		for (k = 0; k < N_OPS; k = k + 1) begin
			op = ops[k];
			for (i = 0; i < N_CORNER; i = i + 1)
				for (j = 0; j < N_CORNER; j = j + 1) begin
					a = corner[i];
					b = corner[j];
					check;
				end
			for (i = 0; i < 32; i = i + 1) begin
				a = $random;
				b = i;
				check;
			end
			for (i = 0; i < 5000; i = i + 1) begin
				a = $random;
				b = $random;
				if (i % 4 == 0) b = a;
				if (i % 8 == 1) b = a ^ 32'h8000_0000;
				check;
			end
		end

		if (errors == 0)
			$display("PASS: nt_alu (%0d checks)", checks);
		else
			$display("FAIL: nt_alu: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
