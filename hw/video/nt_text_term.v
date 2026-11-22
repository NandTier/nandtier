// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier text terminal: an 80 x 25 character screen drawn over the
// video picture, written one character at a time.
//
// Input characters:
//   0x20..0x7E  printed at the cursor; the line wraps after column 79
//   LF (0x0A)   start of the next line, scrolling up at the bottom
//   CR (0x0D)   start of the current line
//   BS (0x08)   cursor one to the left, erasing that character
//   TAB (0x09)  next multiple of 8 columns
//   FF (0x0C) and EOT (0x04) clear the screen
//   anything else is ignored
// Clearing the screen takes about 2000 cycles and scrolling 80; one
// character can wait meanwhile (in_ready low only if a second arrives).
//
// Display: give the pixel position (x, y) every cycle; text_on is 1 three
// cycles later if that pixel is part of a character. Characters are
// 8 x 16 pixels (font rows shown twice), the screen starts at line TOP_Y.
//
// Screen memory is a ring of 25 lines; scrolling moves the ring start
// instead of copying lines.

`timescale 1 ns / 1 ps

module nt_text_term #(
	parameter TOP_Y = 40
) (
	input            clk,
	input            resetn,

	input            in_valid,
	input      [7:0] in_char,
	output           in_ready,

	input      [9:0] x,
	input      [9:0] y,
	output reg       text_on
);
	localparam COLS = 80;
	localparam ROWS = 25;
	localparam CELLS = COLS * ROWS;

	// --- screen memory (one block RAM) ----------------------------------------

	reg  [6:0] screen [0:2047];
	reg        mem_we;
	reg [10:0] mem_waddr;
	reg  [6:0] mem_wdata;
	reg [10:0] mem_raddr;
	reg  [6:0] mem_rdata;

	always @(posedge clk) begin
		if (mem_we)
			screen[mem_waddr] <= mem_wdata;
		mem_rdata <= screen[mem_raddr];
	end

	// line number in the ring -> address of its first character
	function [10:0] line_base(input [4:0] line);
		line_base = {line, 6'd0} + {2'd0, line, 4'd0};   // line * 80
	endfunction

	// screen row (0 = top) -> line in the ring
	function [4:0] ring_line(input [4:0] row, input [4:0] first);
		reg [5:0] sum;
		begin
			sum       = {1'b0, row} + {1'b0, first};
			if (sum >= ROWS)
				sum = sum - 6'd25;
			ring_line = sum[4:0];
		end
	endfunction

	// --- writing ---------------------------------------------------------------

	localparam [1:0] W_CLEAR_ALL = 2'd0, W_IDLE = 2'd1, W_CLEAR_LINE = 2'd2;

	reg [1:0]  wstate;
	reg [4:0]  first;           // ring line shown at the top of the screen
	reg [4:0]  crow;            // cursor row on screen
	reg [6:0]  ccol;            // cursor column
	reg        wrap_pending;    // last write filled column 79
	reg [10:0] clear_addr, clear_end;

	reg        pending;
	reg [7:0]  pending_char;

	assign in_ready = !pending;

	wire [10:0] cursor_addr = line_base(ring_line(crow, first)) + {4'd0, ccol};

	// go to the start of the next line, scrolling if on the last one
	task new_line;
		begin
			ccol         <= 7'd0;
			wrap_pending <= 1'b0;
			if (crow != ROWS - 1) begin
				crow <= crow + 5'd1;
			end else begin
				// the old top line becomes the new bottom line: blank it
				first      <= first == ROWS - 1 ? 5'd0 : first + 5'd1;
				clear_addr <= line_base(first);
				clear_end  <= line_base(first) + 11'd79;
				wstate     <= W_CLEAR_LINE;
			end
		end
	endtask

	always @(posedge clk) begin
		mem_we <= 1'b0;

		if (in_valid && in_ready) begin
			pending      <= 1'b1;
			pending_char <= in_char;
		end

		if (!resetn) begin
			wstate       <= W_CLEAR_ALL;
			clear_addr   <= 11'd0;
			clear_end    <= CELLS - 1;
			first        <= 5'd0;
			crow         <= 5'd0;
			ccol         <= 7'd0;
			wrap_pending <= 1'b0;
			pending      <= 1'b0;
		end else begin
			case (wstate)
				W_CLEAR_ALL, W_CLEAR_LINE: begin
					mem_we     <= 1'b1;
					mem_waddr  <= clear_addr;
					mem_wdata  <= 7'h20;
					clear_addr <= clear_addr + 11'd1;
					if (clear_addr == clear_end)
						wstate <= W_IDLE;
				end

				default: if (pending) begin
					pending <= 1'b0;
					case (pending_char)
						8'h0A: new_line;
						8'h0D: begin
							ccol         <= 7'd0;
							wrap_pending <= 1'b0;
						end
						8'h08: if (ccol != 7'd0 && !wrap_pending) begin
							ccol      <= ccol - 7'd1;
							mem_we    <= 1'b1;
							mem_waddr <= cursor_addr - 11'd1;
							mem_wdata <= 7'h20;
						end else if (wrap_pending) begin
							wrap_pending <= 1'b0;
							mem_we       <= 1'b1;
							mem_waddr    <= cursor_addr;
							mem_wdata    <= 7'h20;
						end
						8'h09: if (ccol >= COLS - 8 || wrap_pending)
							new_line;
						else
							ccol <= {ccol[6:3] + 4'd1, 3'd0};
						8'h0C, 8'h04: begin
							wstate       <= W_CLEAR_ALL;
							clear_addr   <= 11'd0;
							clear_end    <= CELLS - 1;
							first        <= 5'd0;
							crow         <= 5'd0;
							ccol         <= 7'd0;
							wrap_pending <= 1'b0;
						end
						default: if (pending_char >= 8'h20 && pending_char < 8'h7F) begin
							if (wrap_pending) begin
								// finish the wrap first, print this character after it
								new_line;
								pending <= 1'b1;
							end else begin
								mem_we    <= 1'b1;
								mem_waddr <= cursor_addr;
								mem_wdata <= pending_char[6:0];
								if (ccol == COLS - 1)
									wrap_pending <= 1'b1;
								else
									ccol <= ccol + 7'd1;
							end
						end
					endcase
				end
			endcase
		end
	end

	// --- display ---------------------------------------------------------------

	// stage 0: which character cell is (x, y) in
	wire [9:0] ty      = y - TOP_Y[9:0];
	wire       in_text = x < COLS * 8 && y >= TOP_Y && y < TOP_Y + ROWS * 16;
	wire [4:0] row     = ty[8:4];

	always @(posedge clk)
		mem_raddr <= line_base(ring_line(row, first)) + {4'd0, x[9:3]};

	// stage 1: character arrives; keep the pixel position within the cell
	reg       in_text_1, in_text_2;
	reg [2:0] cell_x_1, cell_x_2;
	reg [2:0] glyph_row_1, glyph_row_2;

	always @(posedge clk) begin
		in_text_1   <= in_text;
		cell_x_1    <= x[2:0];
		glyph_row_1 <= ty[3:1];
		in_text_2   <= in_text_1;
		cell_x_2    <= cell_x_1;
		glyph_row_2 <= glyph_row_1;
	end

	// stage 2: font lookup; glyph columns 0..4 sit in cell columns 1..5
	wire lit;
	nt_font_rom u_font (
		.code(mem_rdata),
		.row (glyph_row_2),
		.col (cell_x_2 - 3'd1),
		.lit (lit)
	);

	always @(posedge clk)
		text_on <= in_text_2 && lit;

endmodule
