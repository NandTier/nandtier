// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_ppu against a per-pixel reference model of the rules in its header:
// random tiles, tile map and palettes; 40 sprites using every feature
// (both sizes, flips, behind-background, negative x, top/bottom edges,
// more than 16 on one line); scrolling with a split. Two whole frames are
// compared pixel by pixel, with different scroll, split and layer settings.

`timescale 1 ns / 1 ps

module tb_ppu;

	reg clk = 0;
	always #5 clk = ~clk;
	reg resetn = 0;

	wire [9:0]  x, y;
	wire        visible, hsync, vsync;
	reg         valid = 0;
	reg  [15:0] addr;
	reg  [31:0] wdata;
	reg  [3:0]  wstrb;
	wire        ready;
	wire [31:0] rdata;
	wire [11:0] rgb;
	wire        active, term_on;

	nt_video_timing u_timing (.clk(clk), .resetn(resetn), .x(x), .y(y),
	                          .visible(visible), .hsync(hsync), .vsync(vsync));

	nt_ppu dut (
		.clk(clk), .resetn(resetn),
		.valid(valid), .addr(addr), .wdata(wdata), .wstrb(wstrb), .ready(ready), .rdata(rdata),
		.x(x), .y(y), .rgb(rgb), .active(active), .term_on(term_on)
	);

	// --- model copy of video memory ---------------------------------------------------

	reg [11:0] m_pal [0:127];
	reg [31:0] m_oam [0:63];
	reg [11:0] m_nt  [0:2047];
	reg [31:0] m_chr [0:2047];
	reg [2:0]  m_ctrl;
	reg [8:0]  m_sx;
	reg [7:0]  m_sy, m_split;

	task write(input [15:0] a, input [31:0] d);
		begin
			@(posedge clk);
			valid <= 1; addr <= a; wdata <= d; wstrb <= 4'hF;
			@(posedge clk);
			valid <= 0;
		end
	endtask

	integer i, j;

	// --- reference: picture pixel (px, py) -> palette entry -------------------------

	// sprites on line py, first 16 in OAM order
	integer line_spr [0:15];
	integer n_line_spr, cur_line;

	task find_sprites(input integer py);
		integer k, h;
		begin
			n_line_spr = 0;
			for (k = 0; k < 64; k = k + 1) begin
				h = m_oam[k][29] ? 16 : 8;
				if (py >= m_oam[k][7:0] && py - m_oam[k][7:0] < h && n_line_spr < 16) begin
					line_spr[n_line_spr] = k;
					n_line_spr = n_line_spr + 1;
				end
			end
			cur_line = py;
		end
	endtask

	function [6:0] expected(input integer px, input integer py);
		integer sxs, sys, mapx, e, trow, k, bgc, s, w, h, sxp, dx, r, half, col, tile, sc, best;
		reg [31:0] o;
		begin
			sxs  = py < m_split ? 0 : m_sx;
			sys  = py < m_split ? py : (py + m_sy) % 256;
			mapx = (px + sxs) % 512;
			e    = m_nt[(sys / 8) * 64 + mapx / 8];
			trow = e[11] ? 7 - sys % 8 : sys % 8;
			k    = e[10] ? 7 - mapx % 8 : mapx % 8;
			bgc  = (m_chr[e[7:0] * 8 + trow] >> (4 * k)) & 15;
			if (!m_ctrl[0]) bgc = 0;

			best = -1;
			for (s = n_line_spr - 1; s >= 0; s = s - 1) begin
				o   = m_oam[line_spr[s]];
				w   = o[29] ? 16 : 8;
				h   = w;
				sxp = o[16] ? o[16:8] - 512 : o[16:8];
				dx  = px - sxp;
				if (dx >= 0 && dx < w) begin
					r    = py - o[7:0];
					if (o[28]) r = h - 1 - r;
					half = dx / 8;
					col  = o[29] ? (o[27] ? 1 - half : half) : 0;
					tile = (o[24:17] + (r >= 8 ? 16 : 0) + col) % 256;
					k    = o[27] ? 7 - dx % 8 : dx % 8;
					sc   = (m_chr[tile * 8 + r % 8] >> (4 * k)) & 15;
					if (sc != 0) best = line_spr[s];      // lower index drawn later
				end
			end

			expected = bgc != 0 ? {1'b0, e[9:8], bgc[3:0]} : 7'd0;
			if (best >= 0 && m_ctrl[1]) begin
				o   = m_oam[best];
				sxp = o[16] ? o[16:8] - 512 : o[16:8];
				dx  = px - sxp;
				w   = o[29] ? 16 : 8;
				r   = py - o[7:0];
				if (o[28]) r = w - 1 - r;
				half = dx / 8;
				col  = o[29] ? (o[27] ? 1 - half : half) : 0;
				tile = (o[24:17] + (r >= 8 ? 16 : 0) + col) % 256;
				k    = o[27] ? 7 - dx % 8 : dx % 8;
				sc   = (m_chr[tile * 8 + r % 8] >> (4 * k)) & 15;
				if (!o[30] || bgc == 0)
					expected = {1'b1, o[26:25], sc[3:0]};
			end
		end
	endfunction

	// --- compare the output, delayed by 3 cycles --------------------------------------

	reg [9:0] xd [0:2];
	reg [9:0] yd [0:2];
	integer   errors = 0, checked = 0;
	reg       checking = 0;
	integer   px, py;
	reg [6:0] want;

	always @(posedge clk) begin
		xd[0] <= x; xd[1] <= xd[0]; xd[2] <= xd[1];
		yd[0] <= y; yd[1] <= yd[0]; yd[2] <= yd[1];
	end

	always @(negedge clk) if (checking) begin
		if (active !== (xd[2] >= 64 && xd[2] < 576 && yd[2] < 480)) begin
			errors = errors + 1;
			if (errors < 10) $display("  active wrong at %0d,%0d", xd[2], yd[2]);
		end
		if (active && !xd[2][0] && !yd[2][0]) begin
			px = (xd[2] - 64) / 2;
			py = yd[2] / 2;
			if (py != cur_line) find_sprites(py);
			want = expected(px, py);
			checked = checked + 1;
			if (rgb !== m_pal[want]) begin
				errors = errors + 1;
				if (errors < 10)
					$display("  pixel %0d,%0d: rgb %03x, expected %03x (palette entry %0d)",
					         px, py, rgb, m_pal[want], want);
			end
		end
	end

	task run_frame;
		begin
			// wait for the start of a frame, check all of it
			while (!(x == 0 && y == 0)) @(posedge clk);
			cur_line = -1;
			checking = 1;
			while (!(x == 0 && y == 480)) @(posedge clk);
			repeat (4) @(posedge clk);
			checking = 0;
		end
	endtask

	task set_regs(input [2:0] c, input [8:0] sx, input [7:0] sy, input [7:0] sp);
		begin
			m_ctrl = c; m_sx = sx; m_sy = sy; m_split = sp;
			write(16'h0000, c);
			write(16'h0004, sx);
			write(16'h0008, sy);
			write(16'h000C, sp);
		end
	endtask

	reg [31:0] o;

	initial begin
		repeat (3) @(posedge clk);
		resetn <= 1;

		for (i = 0; i < 128; i = i + 1) begin m_pal[i] = $random; write(16'h0400 + i * 4, m_pal[i]); end
		for (i = 0; i < 2048; i = i + 1) begin
			m_chr[i] = $random;
			if (i % 5 == 0) m_chr[i] = m_chr[i] & 32'h0F0F_F00F;   // some transparent pixels
			write(16'h4000 + i * 4, m_chr[i]);
		end
		for (i = 0; i < 2048; i = i + 1) begin m_nt[i] = $random; write(16'h2000 + i * 4, m_nt[i]); end

		for (i = 0; i < 64; i = i + 1) begin
			o = $random;
			if (i < 20) begin
				o[7:0] = 100 - i % 3;           // 20 sprites on lines 100..: the limit
				o[16:8] = i * 12;
			end else if (i == 20) begin
				o[7:0] = 0; o[16:8] = 9'h1FC;   // top edge, x = -4
			end else if (i == 21) begin
				o[7:0] = 232; o[16:8] = 250;    // bottom and right edge
			end else if (i >= 40) begin
				o[7:0] = 8'hF0 | i[3:0];        // off screen
			end
			m_oam[i] = o;
			write(16'h0800 + i * 4, o);
		end

		set_regs(3'b011, 9'd77, 8'd13, 8'd16);
		run_frame;
		set_regs(3'b011, 9'd300, 8'd250, 8'd0);
		run_frame;
		set_regs(3'b001, 9'd5, 8'd0, 8'd240);       // background only, no scrolling
		run_frame;

		if (errors == 0)
			$display("PASS: nt_ppu (%0d pixels in 3 frames)", checked);
		else
			$display("FAIL: nt_ppu: %0d errors", errors);
		$finish;
	end

endmodule
