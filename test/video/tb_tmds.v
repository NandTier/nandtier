// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_tmds_encoder: every symbol decodes back to its data byte (DVI 1.0
// decoding), the four control symbols are right, the running disparity
// of the line stays within +-10 and each data run is balanced at every
// blanking start.

`timescale 1 ns / 1 ps

module tb_tmds;

	reg clk = 0;
	always #5 clk = ~clk;
	reg        resetn = 0;
	reg        de;
	reg  [7:0] data;
	reg  [1:0] ctrl;
	wire [9:0] symbol;

	nt_tmds_encoder dut (.clk(clk), .resetn(resetn), .de(de), .data(data), .ctrl(ctrl), .symbol(symbol));

	function [7:0] decode(input [9:0] s);
		reg [7:0] d;
		integer i;
		begin
			d = s[9] ? ~s[7:0] : s[7:0];
			decode[0] = d[0];
			for (i = 1; i < 8; i = i + 1)
				decode[i] = s[8] ? d[i] ^ d[i-1] : !(d[i] ^ d[i-1]);
		end
	endfunction

	function integer balance(input [9:0] s);
		integer i;
		begin
			balance = 0;
			for (i = 0; i < 10; i = i + 1)
				balance = balance + (s[i] ? 1 : -1);
		end
	endfunction

	integer errors = 0, checks = 0, line, px, run;
	reg [7:0] prev_data;
	reg       prev_de;
	reg [1:0] prev_ctrl;
	reg [9:0] ctrl_sym [0:3];

	initial begin
		ctrl_sym[0] = 10'b1101010100; ctrl_sym[1] = 10'b0010101011;
		ctrl_sym[2] = 10'b0101010100; ctrl_sym[3] = 10'b1010101011;
	end

	// check each symbol against the input of the cycle before
	always @(posedge clk) if (resetn) begin
		#1;
		if (prev_de) begin
			checks = checks + 1;
			run = run + balance(symbol);
			if (decode(symbol) !== prev_data) begin
				errors = errors + 1;
				if (errors < 10) $display("  data %02x encoded as %b decodes to %02x", prev_data, symbol, decode(symbol));
			end
			if (run > 10 || run < -10) begin
				errors = errors + 1;
				if (errors < 10) $display("  running disparity %0d", run);
			end
		end else if (prev_de === 1'b0) begin
			if (symbol !== ctrl_sym[prev_ctrl]) begin
				errors = errors + 1;
				$display("  control %b encoded as %b", prev_ctrl, symbol);
			end
			run = 0;
		end
	end

	always @(posedge clk) begin
		prev_de   <= de;
		prev_data <= data;
		prev_ctrl <= ctrl;
	end

	initial begin
		de = 0; ctrl = 0; data = 0; run = 0;
		repeat (3) @(posedge clk);
		resetn <= 1;
		for (line = 0; line < 200; line = line + 1) begin
			for (px = 0; px < 640; px = px + 1) begin
				@(negedge clk);
				de = 1;
				case (line % 4)
					0: data = $random;
					1: data = px;                       // ramps
					2: data = line[0] ? 8'hFF : 8'h00;  // flat colours
					3: data = px[0] ? 8'h10 : 8'hEF;
				endcase
			end
			for (px = 0; px < 160; px = px + 1) begin
				@(negedge clk);
				de = 0;
				ctrl = px / 40;
			end
		end
		@(negedge clk);
		@(negedge clk);

		if (errors == 0)
			$display("PASS: nt_tmds_encoder (%0d symbols)", checks);
		else
			$display("FAIL: nt_tmds_encoder: %0d errors", errors);
		$finish;
	end

endmodule
