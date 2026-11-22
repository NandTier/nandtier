// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier picture processing unit: an NES-style tile and sprite engine.
// The picture is 256 x 240 pixels, shown at 2x in the middle of the
// 640 x 480 output (columns 64..575).
//
// Video memory (written by the CPU, write only):
//   CHR      256 tiles of 8 x 8 pixels, 4 bits per pixel. Word tile*8+row
//            holds one tile row; pixel k (0 = left) is in bits 4k+3..4k.
//   NAMETAB  64 x 32 tile map (two screens wide), word row*64+col:
//            bits 7:0 tile, 9:8 palette, 10 flip horizontally, 11 vertically
//   OAM      64 sprites, one word each:
//            bits 7:0 y (top line; 240..255 is off screen), 16:8 x (9-bit
//            two's complement, -256..255), 24:17 tile, 26:25 palette,
//            27 flip horizontally, 28 vertically, 29 16 x 16 (tiles t, t+1,
//            t+16, t+17), 30 behind the background
//   PALETTE  128 colours, 12-bit 0xRGB: 0..63 background palettes 0..3 (16
//            colours each), 64..127 sprite palettes 0..3. Colour 0 of a
//            tile is transparent; where every layer is transparent, entry
//            0 (the backdrop) shows.
//
// Up to 16 sprites per line; a lower OAM index is drawn in front.
// Lines above SPLIT are not scrolled (a fixed status bar).
//
// Registers and memory, byte offsets:
//   0x0000 CTRL      bit 0 background on, bit 1 sprites on, bit 2 text
//                    terminal overlay on (reset: 0b100)
//   0x0004 SCROLL_X  bits 8:0, scroll position in the 512-pixel-wide map
//   0x0008 SCROLL_Y  bits 7:0, in the 256-pixel-high map
//   0x000C SPLIT     bits 7:0, first scrolled line
//   0x0010 STATUS    read only: bit 0 vertical blank, bits 31:16 frame count
//   0x0400 PALETTE   128 words
//   0x0800 OAM       64 words
//   0x2000 NAMETAB   2048 words
//   0x4000 CHR       2048 words
//
// Rendering: picture line n is drawn into one half of a line buffer while
// line n-1 is shown from the other half, i.e. during output lines 2n-2 and
// 2n-1 (1600 clock cycles; a line with 16 wide sprites takes about 820).
// Output: colour for the pixel (x, y) given at t comes out at t+3.

`timescale 1 ns / 1 ps

module nt_ppu (
	input             clk,
	input             resetn,

	input             valid,
	input      [15:0] addr,
	input      [31:0] wdata,
	input      [ 3:0] wstrb,
	output            ready,
	output     [31:0] rdata,

	input      [ 9:0] x,            // output pixel position, from nt_video_timing
	input      [ 9:0] y,
	output reg [11:0] rgb,          // t+3
	output reg        active,       // t+3: inside the picture area
	output            term_on       // CTRL bit 2
);
	// --- registers -----------------------------------------------------------------

	reg [2:0]  ctrl;
	reg [8:0]  scroll_x;
	reg [7:0]  scroll_y;
	reg [7:0]  split;
	reg [15:0] frame;

	wire vblank = y >= 10'd480;
	wire write  = valid && |wstrb;

	always @(posedge clk) begin
		if (!resetn) begin
			ctrl     <= 3'b100;
			scroll_x <= 9'd0;
			scroll_y <= 8'd0;
			split    <= 8'd0;
		end else if (write && addr[15:10] == 6'd0) begin
			case (addr[4:2])
				3'd0: ctrl     <= wdata[2:0];
				3'd1: scroll_x <= wdata[8:0];
				3'd2: scroll_y <= wdata[7:0];
				3'd3: split    <= wdata[7:0];
				default: ;
			endcase
		end
	end

	// frame counter: counts at the start of vertical blank
	always @(posedge clk) begin
		if (!resetn)
			frame <= 16'd0;
		else if (x == 10'd0 && y == 10'd480)
			frame <= frame + 16'd1;
	end

	assign term_on = ctrl[2];
	assign ready   = valid;
	assign rdata   = addr[15:10] != 6'd0 ? 32'd0 :
	                 addr[4:2] == 3'd0   ? {29'd0, ctrl} :
	                 addr[4:2] == 3'd1   ? {23'd0, scroll_x} :
	                 addr[4:2] == 3'd2   ? {24'd0, scroll_y} :
	                 addr[4:2] == 3'd3   ? {24'd0, split} :
	                 addr[4:2] == 3'd4   ? {frame, 15'd0, vblank} : 32'd0;


	// --- video memory (CPU writes, renderer reads) -----------------------------------

	reg [11:0] palette [0:127];
	reg [31:0] oam     [0:63];
	reg [11:0] nametab [0:2047];
	reg [31:0] chr     [0:2047];

	always @(posedge clk) begin
		if (write && addr[15:9] == 7'b0000_010)            // 0x0400..0x05FF
			palette[addr[8:2]] <= wdata[11:0];
		if (write && addr[15:8] == 8'h08)                  // 0x0800..0x08FF
			oam[addr[7:2]] <= wdata;
		if (write && addr[15:13] == 3'b001)                // 0x2000..0x3FFF
			nametab[addr[12:2]] <= wdata[11:0];
		if (write && addr[15:13] == 3'b010)                // 0x4000..0x5FFF
			chr[addr[12:2]] <= wdata;
	end

	// renderer read ports: synchronous, the address is combinational from
	// the renderer state, the data is there in the next cycle
	wire [5:0]  oam_ra;
	wire [10:0] nt_ra, chr_ra;
	reg  [31:0] oam_q, chr_q;
	reg  [11:0] nt_q;

	always @(posedge clk) begin
		oam_q <= oam[oam_ra];
		nt_q  <= nametab[nt_ra];
		chr_q <= chr[chr_ra];
	end

	// --- line buffers: two lines each, background and sprite layer ---------------------

	reg  [5:0] bg_line  [0:511];    // {palette, colour}
	reg  [7:0] spr_line [0:511];    // {opaque, behind, palette, colour}

	reg        bg_we, spr_we;
	reg  [8:0] bg_wa, spr_wa;
	reg  [5:0] bg_wd;
	reg  [7:0] spr_wd;
	wire [8:0] show_ra;
	reg  [5:0] bg_q;
	reg  [7:0] spr_q;

	always @(posedge clk) begin
		if (bg_we)  bg_line[bg_wa]   <= bg_wd;
		if (spr_we) spr_line[spr_wa] <= spr_wd;
		bg_q  <= bg_line[show_ra];
		spr_q <= spr_line[show_ra];
	end

	// --- renderer ----------------------------------------------------------------------

	// Each memory read takes two states: one where the address is applied,
	// one where the data is there.
	localparam [3:0] R_IDLE    = 4'd0,
	                 R_BG_NT   = 4'd1,   // tile map address
	                 R_BG_CHR  = 4'd2,   // tile map entry here; tile row address
	                 R_BG_PIX  = 4'd3,   // tile row here; 8 pixels, one per cycle
	                 R_EVAL    = 4'd4,   // sprite evaluation, one OAM entry per cycle
	                 R_SP_WAIT = 4'd5,   // OAM address of the sprite to draw
	                 R_SP_OAM  = 4'd6,   // OAM entry here
	                 R_SP_CHR  = 4'd7,   // tile row address
	                 R_SP_PIX  = 4'd8;   // tile row here; 8 pixels

	reg [3:0]  rstate;
	reg [7:0]  line;            // picture line being drawn
	reg [8:0]  sx;              // horizontal scroll of this line
	reg [7:0]  sy;              // map line of this line
	reg [5:0]  tile_i;          // background tile 0..32 of this line
	reg [2:0]  pix;             // pixel within the tile row
	reg [8:0]  clr_x;           // sprite layer clear position, done at 256

	reg [5:0]  found [0:15];    // sprites on this line (OAM index), in OAM order
	reg [4:0]  nfound;
	reg [6:0]  ev_i;            // OAM entry being read; entry ev_i-1 is tested
	reg [4:0]  dr_j;            // drawing found[dr_j-1], from the last one down
	reg        s_half;          // second 8 pixels of a 16-wide sprite
	reg        s_wide, s_behind, s_hflip;
	reg [1:0]  s_pal;
	reg [8:0]  s_x;
	reg [7:0]  s_tile;
	reg [3:0]  s_row;

	// start drawing line n during output lines 2n-2 and 2n-1
	wire       start   = x == 10'd0 && ((!y[0] && y < 10'd478) || y == 10'd523);
	wire [7:0] start_n = y == 10'd523 ? 8'd0 : y[8:1] + 8'd1;

	// background: tile map entry and tile row of tile `tile_i`
	assign nt_ra = {sy[7:3], sx[8:3] + tile_i};
	wire [2:0] bg_row = nt_q[11] ? ~sy[2:0] : sy[2:0];

	// sprites: tile of this half (16-wide: t, t+1 above, t+16, t+17 below)
	wire       s_col    = s_wide && (s_half ^ s_hflip);
	wire [7:0] s_tile_n = s_tile + {3'd0, s_row[3], 3'd0, s_col};

	assign chr_ra = rstate == R_SP_CHR || rstate == R_SP_PIX ? {s_tile_n, s_row[2:0]}
	                                                         : {nt_q[7:0], bg_row};

	wire [4:0] dr_idx = dr_j - 5'd1;
	assign oam_ra = rstate == R_EVAL ? ev_i[5:0] : found[dr_idx[3:0]];

	// pixel `pix` of the current tile row
	wire       hflip_now = rstate == R_SP_PIX ? s_hflip : nt_q[10];
	wire [2:0] pix_col   = hflip_now ? ~pix : pix;
	wire [3:0] colour    = chr_q[{pix_col, 2'b00} +: 4];

	wire [9:0] bg_px = {1'b0, tile_i, pix} - {7'd0, sx[2:0]};   // < 256: on the line
	wire [8:0] sp_px = s_x + {5'd0, s_half, pix};               // bit 8: off the line

	// is OAM entry ev_i-1 (in oam_q) on this line?
	wire [7:0] ev_dy = line - oam_q[7:0];
	wire       ev_on = line >= oam_q[7:0] && ev_dy < (oam_q[29] ? 8'd16 : 8'd8);

	always @(posedge clk) begin
		bg_we  <= 1'b0;
		spr_we <= 1'b0;

		if (!resetn) begin
			rstate <= R_IDLE;
			clr_x  <= 9'h100;
		end else begin
			// clear this line's half of the sprite layer while the
			// background is drawn (256 cycles, the background takes 330)
			if (!clr_x[8]) begin
				spr_we <= 1'b1;
				spr_wa <= {line[0], clr_x[7:0]};
				spr_wd <= 8'd0;
				clr_x  <= clr_x + 9'd1;
			end

			case (rstate)
				R_IDLE: if (start) begin
					line   <= start_n;
					sx     <= start_n < split ? 9'd0 : scroll_x;
					sy     <= start_n < split ? start_n : start_n + scroll_y;
					tile_i <= 6'd0;
					clr_x  <= 9'd0;
					rstate <= R_BG_NT;
				end

				R_BG_NT:
					rstate <= R_BG_CHR;

				R_BG_CHR: begin
					pix    <= 3'd0;
					rstate <= R_BG_PIX;
				end

				R_BG_PIX: begin
					if (bg_px < 10'd256) begin
						bg_we <= 1'b1;
						bg_wa <= {line[0], bg_px[7:0]};
						bg_wd <= {nt_q[9:8], colour};
					end
					pix <= pix + 3'd1;
					if (pix == 3'd7) begin
						tile_i <= tile_i + 6'd1;
						if (tile_i == 6'd32) begin
							ev_i   <= 7'd0;
							nfound <= 5'd0;
							rstate <= R_EVAL;
						end else
							rstate <= R_BG_NT;
					end
				end

				R_EVAL: begin
					ev_i <= ev_i + 7'd1;
					if (ev_i != 7'd0 && ev_on && !nfound[4]) begin
						found[nfound[3:0]] <= ev_i[5:0] - 6'd1;
						nfound <= nfound + 5'd1;
					end
					if (ev_i == 7'd64) begin
						dr_j   <= nfound + (ev_on && !nfound[4] ? 5'd1 : 5'd0);
						rstate <= nfound != 5'd0 || (ev_on && !nfound[4]) ? R_SP_WAIT : R_IDLE;
					end
				end

				R_SP_WAIT:
					rstate <= R_SP_OAM;

				R_SP_OAM: begin
					// oam_q: the sprite; work out which row of it is on this line
					s_x      <= oam_q[16:8];
					s_tile   <= oam_q[24:17];
					s_pal    <= oam_q[26:25];
					s_hflip  <= oam_q[27];
					s_wide   <= oam_q[29];
					s_behind <= oam_q[30];
					s_row    <= oam_q[28] ? (oam_q[29] ? 4'd15 : 4'd7) - ev_dy[3:0] : ev_dy[3:0];
					s_half   <= 1'b0;
					rstate   <= R_SP_CHR;
				end

				R_SP_CHR: begin
					pix    <= 3'd0;
					rstate <= R_SP_PIX;
				end

				R_SP_PIX: begin
					if (colour != 4'd0 && !sp_px[8]) begin
						spr_we <= 1'b1;
						spr_wa <= {line[0], sp_px[7:0]};
						spr_wd <= {1'b1, s_behind, s_pal, colour};
					end
					pix <= pix + 3'd1;
					if (pix == 3'd7) begin
						if (s_wide && !s_half) begin
							s_half <= 1'b1;
							rstate <= R_SP_CHR;
						end else begin
							dr_j   <= dr_j - 5'd1;
							rstate <= dr_j == 5'd1 ? R_IDLE : R_SP_WAIT;
						end
					end
				end

				default: rstate <= R_IDLE;
			endcase
		end
	end

	// --- display -----------------------------------------------------------------------

	wire [9:0] pic_x  = x - 10'd64;
	wire       in_pic = x >= 10'd64 && x < 10'd576 && y < 10'd480;

	assign show_ra = {y[1], pic_x[8:1]};

	// t+1: both layers of this pixel
	reg in_pic_1, in_pic_2;
	reg [6:0] pal_idx;

	wire bg_opaque = ctrl[0] && bg_q[3:0] != 4'd0;
	wire use_spr   = ctrl[1] && spr_q[7] && (!spr_q[6] || !bg_opaque);

	always @(posedge clk) begin
		in_pic_1 <= in_pic;
		in_pic_2 <= in_pic_1;
		active   <= in_pic_2;
		pal_idx  <= use_spr   ? {1'b1, spr_q[5:0]} :
		            bg_opaque ? {1'b0, bg_q} : 7'd0;
		rgb      <= palette[pal_idx];
	end

endmodule
