// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// boards/common/ecp5_hdmi_phy.v: the serial bit stream of every lane,
// cut into 10-bit words where the clock lane goes from 0 to 1 (its word is
// 0000011111, bit 0 first), must give back the symbols fed in, one per
// pixel clock, in order, without gaps or repeats.
//
// ODDRX1F is modelled here: D0 and D1 are taken at the rising edge of
// SCLK, D0 is sent during the high half of the clock, D1 during the low.

`timescale 1 ns / 1 ps

module ODDRX1F (input D0, input D1, input SCLK, input RST, output Q);
	reg d0 = 0, d1 = 0;
	always @(posedge SCLK) begin
		d0 <= D0;
		d1 <= D1;
	end
	assign Q = SCLK ? d0 : d1;
endmodule

module tb_ecp5_phy;

	reg clk = 0, clk_5x = 0;
	always #20 clk = !clk;              // 25 MHz pixel clock
	always #4  clk_5x = !clk_5x;        // 125 MHz, in phase

	reg  [9:0] sym0 = 0, sym1 = 0, sym2 = 0;
	wire       tclk;
	wire [2:0] td;

	nt_hdmi_phy u_phy (
		.clk(clk), .clk_5x(clk_5x), .resetn(1'b1),
		.sym0(sym0), .sym1(sym1), .sym2(sym2),
		.tmds_clk_p(tclk), .tmds_clk_n(), .tmds_d_p(td), .tmds_d_n()
	);

	// a new symbol per pixel: a counting pattern, different on each lane
	integer pixel = 0;
	always @(posedge clk) begin
		pixel <= pixel + 1;
		sym0  <= (pixel * 7 + 1) & 10'h3FF;
		sym1  <= (pixel * 13 + 300) & 10'h3FF;
		sym2  <= (pixel * 29 + 700) & 10'h3FF;
	end

	// receiver: one sample in the middle of each bit (2 bits per clk_5x)
	reg [9:0] w0, w1, w2, wc;
	integer   bits = 0, words = 0, errors = 0, first = -1;
	reg [9:0] expect0;
	integer   expect_n;

	always @(clk_5x) begin
		#2;                             // middle of the bit
		w0 = {td[0], w0[9:1]};          // bit 0 first: shift in from the top
		w1 = {td[1], w1[9:1]};
		w2 = {td[2], w2[9:1]};
		wc = {tclk, wc[9:1]};
		bits = bits + 1;
		if (wc == 10'b0000011111) begin // a whole word is in
			if (first < 0) begin
				// find the pixel of this word; the first words are from
				// before any symbol came through
				for (expect_n = 0; expect_n < 400 && ((expect_n * 7 + 1) & 10'h3FF) != w0; expect_n = expect_n + 1)
					;
				if (expect_n < 400)
					first = expect_n;
			end else begin
				expect_n = expect_n + 1;
				if (w0 != ((expect_n * 7 + 1) & 10'h3FF) || w1 != ((expect_n * 13 + 300) & 10'h3FF) ||
				    w2 != ((expect_n * 29 + 700) & 10'h3FF)) begin
					if (errors < 5)
						$display("tb_ecp5_phy: word %0d: got %h %h %h for pixel %0d", words, w0, w1, w2, expect_n);
					errors = errors + 1;
				end
			end
			words = words + 1;
		end
	end

	initial begin
		#20000;                         // 500 pixels
		if (words < 480 || errors != 0 || first < 0)
			$display("FAIL: tb_ecp5_phy: %0d words, %0d wrong", words, errors);
		else
			$display("PASS: tb_ecp5_phy (%0d words on 3 lanes, in order)", words);
		$finish;
	end

endmodule
