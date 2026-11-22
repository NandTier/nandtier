// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_branch: all six conditions on corner-case and random operands.

`timescale 1 ns / 1 ps

module tb_branch;

	reg  [ 2:0] funct3;
	reg  [31:0] a, b;
	wire        taken;

	nt_branch dut (.funct3(funct3), .a(a), .b(b), .taken(taken));

	function expected(input [2:0] f3, input [31:0] a, input [31:0] b);
		case (f3)
			3'b000: expected = a == b;
			3'b001: expected = a != b;
			3'b100: expected = $signed(a) <  $signed(b);
			3'b101: expected = $signed(a) >= $signed(b);
			3'b110: expected = a <  b;
			3'b111: expected = a >= b;
			default: expected = 1'bx;
		endcase
	endfunction

	reg [31:0] corner [0:5];
	initial begin
		corner[0] = 32'h0000_0000; corner[1] = 32'h0000_0001; corner[2] = 32'hffff_ffff;
		corner[3] = 32'h8000_0000; corner[4] = 32'h7fff_ffff; corner[5] = 32'h8000_0001;
	end

	integer errors = 0, checks = 0;
	integer f, i, j;

	task check;
		begin
			#1;
			checks = checks + 1;
			if (taken !== expected(funct3, a, b)) begin
				errors = errors + 1;
				if (errors <= 10)
					$display("  funct3=%b a=%08x b=%08x: got %b", funct3, a, b, taken);
			end
		end
	endtask

	initial begin
		for (f = 0; f < 8; f = f + 1) begin
			if (f == 2 || f == 3)
				f = 4;
			funct3 = f;
			for (i = 0; i < 6; i = i + 1)
				for (j = 0; j < 6; j = j + 1) begin
					a = corner[i];
					b = corner[j];
					check;
				end
			for (i = 0; i < 5000; i = i + 1) begin
				a = $random;
				b = i % 3 == 0 ? a : $random;
				check;
			end
		end

		if (errors == 0)
			$display("PASS: nt_branch (%0d checks)", checks);
		else
			$display("FAIL: nt_branch: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
