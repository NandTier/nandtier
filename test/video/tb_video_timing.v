// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_video_timing over two frames: 800 x 525 cycles per frame, 640 x 480
// visible pixels, hsync low for 96 cycles starting at x = 656, vsync low
// for 2 lines starting at line 490, and x/y match the counts.

`timescale 1 ns / 1 ps

module tb_video_timing;

	reg clk = 0;
	always #5 clk = ~clk;
	reg resetn = 0;

	wire [9:0] x, y;
	wire       visible, hsync, vsync;

	nt_video_timing dut (.clk(clk), .resetn(resetn), .x(x), .y(y),
	                     .visible(visible), .hsync(hsync), .vsync(vsync));

	integer errors = 0;
	integer cx, cy, n_visible, n_hs_low, n_vs_low_lines;
	integer frame;

	task check_eq(input integer got, input integer want, input [8*24-1:0] what);
		if (got !== want) begin
			errors = errors + 1;
			$display("  %0s: got %0d, expected %0d", what, got, want);
		end
	endtask

	initial begin
		repeat (3) @(posedge clk);
		resetn <= 1;
		// start counting at the first pixel of a frame
		@(posedge clk); #1;
		while (x !== 0 || y !== 0) begin @(posedge clk); #1; end
		for (frame = 0; frame < 2; frame = frame + 1) begin
			n_visible = 0; n_vs_low_lines = 0;
			for (cy = 0; cy < 525; cy = cy + 1) begin
				n_hs_low = 0;
				for (cx = 0; cx < 800; cx = cx + 1) begin
					#1;
					if (x !== cx || y !== cy) begin
						errors = errors + 1;
						if (errors < 10) $display("  position %0d,%0d, expected %0d,%0d", x, y, cx, cy);
					end
					if (visible !== (cx < 640 && cy < 480)) begin
						errors = errors + 1;
						if (errors < 10) $display("  visible wrong at %0d,%0d", cx, cy);
					end
					if (hsync !== !(cx >= 656 && cx < 752)) begin
						errors = errors + 1;
						if (errors < 10) $display("  hsync wrong at %0d,%0d", cx, cy);
					end
					if (vsync !== !(cy >= 490 && cy < 492)) begin
						errors = errors + 1;
						if (errors < 10) $display("  vsync wrong at %0d,%0d", cx, cy);
					end
					n_visible = n_visible + visible;
					n_hs_low  = n_hs_low + !hsync;
					if (cx == 0) n_vs_low_lines = n_vs_low_lines + !vsync;
					@(posedge clk);
				end
				check_eq(n_hs_low, 96, "hsync width");
			end
			check_eq(n_visible, 640 * 480, "visible pixels");
			check_eq(n_vs_low_lines, 2, "vsync lines");
		end

		if (errors == 0)
			$display("PASS: nt_video_timing");
		else
			$display("FAIL: nt_video_timing: %0d errors", errors);
		$finish;
	end

endmodule
