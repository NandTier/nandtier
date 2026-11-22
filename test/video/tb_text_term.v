// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_text_term against a reference model of the 80 x 25 screen kept in
// this testbench:
//   - printing, CR, LF, TAB, BS, line wrap, scrolling, clear screen
//   - the screen memory read back in display order
//   - text_on for every pixel of a few rows, compared with the font
//     (pipeline alignment and glyph placement)

`timescale 1 ns / 1 ps

module tb_text_term;

	reg clk = 0;
	always #5 clk = ~clk;
	reg resetn = 0;

	reg        in_valid = 0;
	reg  [7:0] in_char;
	wire       in_ready;
	reg  [9:0] x = 0, y = 0;
	wire       text_on;

	nt_text_term #(.TOP_Y(40)) dut (
		.clk(clk), .resetn(resetn),
		.in_valid(in_valid), .in_char(in_char), .in_ready(in_ready),
		.x(x), .y(y), .text_on(text_on)
	);

	// reference font lookup (same ROM, used to check placement and timing)
	reg  [6:0] f_code;
	reg  [2:0] f_row, f_col;
	wire       f_lit;
	nt_font_rom u_ref_font (.code(f_code), .row(f_row), .col(f_col), .lit(f_lit));

	// --- reference model ---------------------------------------------------------

	reg [7:0] model [0:24][0:79];
	integer   m_row, m_col, r, c;
	reg       m_wrap;

	task model_clear;
		begin
			for (r = 0; r < 25; r = r + 1)
				for (c = 0; c < 80; c = c + 1)
					model[r][c] = " ";
			m_row = 0; m_col = 0; m_wrap = 0;
		end
	endtask

	task model_newline;
		begin
			m_col = 0; m_wrap = 0;
			if (m_row < 24) m_row = m_row + 1;
			else begin
				for (r = 0; r < 24; r = r + 1)
					for (c = 0; c < 80; c = c + 1)
						model[r][c] = model[r + 1][c];
				for (c = 0; c < 80; c = c + 1)
					model[24][c] = " ";
			end
		end
	endtask

	task model_put(input [7:0] ch);
		begin
			case (ch)
				8'h0A: model_newline;
				8'h0D: begin m_col = 0; m_wrap = 0; end
				8'h08: if (m_wrap) begin m_wrap = 0; model[m_row][m_col] = " "; end
				       else if (m_col > 0) begin m_col = m_col - 1; model[m_row][m_col] = " "; end
				8'h09: if (m_col >= 72 || m_wrap) model_newline; else m_col = (m_col / 8 + 1) * 8;
				8'h0C, 8'h04: model_clear;
				default: if (ch >= 8'h20 && ch < 8'h7F) begin
					if (m_wrap) model_newline;
					model[m_row][m_col] = ch;
					if (m_col == 79) m_wrap = 1; else m_col = m_col + 1;
				end
			endcase
		end
	endtask

	// --- stimulus ------------------------------------------------------------------

	integer errors = 0, i, j;

	task send(input [7:0] ch);
		begin
			@(posedge clk);
			in_valid <= 1;
			in_char  <= ch;
			@(posedge clk);
			while (!in_ready) @(posedge clk);
			in_valid <= 0;
			model_put(ch);
			repeat (2) @(posedge clk);
			while (dut.wstate != 1 || dut.pending) @(posedge clk);   // wait until done
		end
	endtask

	task send_str(input [8*100-1:0] s);
		integer k;
		begin
			for (k = 99; k >= 0; k = k - 1)
				if (s[k*8 +: 8] != 0)
					send(s[k*8 +: 8]);
		end
	endtask

	function [7:0] screen_at(input integer row, input integer col);
		integer line;
		begin
			line = (row + dut.first) % 25;
			screen_at = dut.screen[line * 80 + col];
		end
	endfunction

	task compare_screen(input [8*20-1:0] when);
		integer bad;
		begin
			bad = 0;
			for (r = 0; r < 25; r = r + 1)
				for (c = 0; c < 80; c = c + 1)
					if (screen_at(r, c) !== model[r][c]) begin
						bad = bad + 1;
						if (bad < 5) $display("  %0s: row %0d col %0d is %02x, expected %02x",
						                      when, r, c, screen_at(r, c), model[r][c]);
					end
			if (bad) errors = errors + 1;
		end
	endtask

	// scan rows of pixels; text_on arrives 3 cycles after (x, y)
	task compare_pixels(input integer first_row, input integer rows);
		integer px, py, bad;
		reg [9:0] hx [0:3];
		reg [9:0] hy [0:3];
		integer   k;
		reg       want;
		begin
			bad = 0;
			for (py = 40 + first_row * 16; py < 40 + (first_row + rows) * 16; py = py + 1)
				for (px = 0; px < 640 + 3; px = px + 1) begin
					@(negedge clk);
					for (k = 3; k > 0; k = k - 1) begin hx[k] = hx[k-1]; hy[k] = hy[k-1]; end
					hx[0] = px; hy[0] = py;
					if (px < 640) begin x = px; y = py; end
					if (px >= 3) begin
						f_code = model[(hy[3] - 40) / 16][hx[3] / 8];
						f_row  = ((hy[3] - 40) % 16) / 2;
						f_col  = hx[3] % 8 - 1;
						#1 want = hx[3] % 8 >= 1 && hx[3] % 8 <= 5 && f_lit;
						if (text_on !== want) begin
							bad = bad + 1;
							if (bad < 5) $display("  pixel %0d,%0d: text_on=%b expected %b", hx[3], hy[3], text_on, want);
						end
					end
				end
			if (bad) errors = errors + 1;
		end
	endtask

	initial begin
		model_clear;
		repeat (3) @(posedge clk);
		resetn <= 1;
		repeat (2100) @(posedge clk);       // initial clear
		compare_screen("after reset");

		send_str("Hello, NandTier!\r\n");
		send_str("tab\tstop\tagain\n");
		send_str("backspace: abcd");
		send(8'h08); send(8'h08); send_str("XY\n");
		for (i = 0; i < 85; i = i + 1) send("a" + i % 26);     // wraps after column 79
		send_str("\r\n");
		for (i = 0; i < 80; i = i + 1) send("0" + i % 10);     // exactly one line, no blank line
		send_str("\r\nend of first part\r\n");
		compare_screen("before scrolling");
		compare_pixels(0, 3);

		for (j = 0; j < 40; j = j + 1) begin                    // scroll a lot
			send_str("line ");
			send("0" + j / 10); send("0" + j % 10);
			send_str(" ~!@#$%^&*()_+{}|:<>?`-=[]\\;',./\r\n");
		end
		compare_screen("after scrolling");
		compare_pixels(20, 5);

		send(8'h0C);                                            // clear screen
		send_str("after clear\r\n");
		compare_screen("after clear");
		compare_pixels(0, 1);

		if (errors == 0)
			$display("PASS: nt_text_term");
		else
			$display("FAIL: nt_text_term: %0d errors", errors);
		$finish;
	end

endmodule
