// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// SD card in SPI mode (SDHC: block addresses, 512-byte blocks), enough for
// fw/common/sd.c: CMD0, CMD8, CMD55 + ACMD41, CMD58, CMD16, CMD17 (read)
// and CMD24 (write). CRCs are not checked.
//
// The card holds BLOCKS blocks from block BASE on, loaded from INIT_FILE
// ($readmemh bytes, e.g. from `sw/mkcarts.py --hex`); other blocks read as
// zeros and ignore writes.
//
// SPI mode 0: MOSI is sampled on the rising edge of SCK, MISO changes on
// the falling edge.

`timescale 1 ns / 1 ps

module sd_card_model #(
	parameter integer BASE      = 8192,
	parameter integer BLOCKS    = 512,
	parameter         INIT_FILE = ""
) (
	input      cs,                  // active low
	input      sck,
	input      mosi,
	output reg miso = 1'b1
);
	reg [7:0] mem [0:BLOCKS * 512 - 1];
	integer   i;

	initial begin
		for (i = 0; i < BLOCKS * 512; i = i + 1)
			mem[i] = 8'h00;
		if (INIT_FILE != "")
			$readmemh(INIT_FILE, mem);
	end

	// --- answer queue: bytes the card sends next ---------------------------------------

	reg [7:0] q [0:1023];
	integer   q_head = 0, q_tail = 0;

	task send(input [7:0] b);
		begin
			q[q_tail % 1024] = b;
			q_tail = q_tail + 1;
		end
	endtask

	// --- state ------------------------------------------------------------------------

	reg [7:0]  in_byte;
	integer    bits = 0;
	reg [7:0]  out_byte = 8'hFF;
	reg [7:0]  cmd [0:5];
	integer    cmd_len = 0;
	reg        idle = 1, app = 0;
	integer    acmd41_tries = 0;
	integer    reads = 0, writes = 0, errors = 0;

	// receiving a write: 0 no, 1 waiting for the start token, 2 data
	integer    wr_state = 0, wr_count = 0;
	reg [31:0] wr_block;
	reg [7:0]  wr_buf [0:511];

	function [31:0] arg(input dummy);
		arg = {cmd[1], cmd[2], cmd[3], cmd[4]};
	endfunction

	function in_range(input [31:0] block);
		in_range = block >= BASE && block < BASE + BLOCKS;
	endfunction

	task command;
		reg [5:0]  index;
		reg [31:0] a;
		integer    k;
		begin
			index = cmd[0][5:0];
			a = arg(0);
			send(8'hFF);                                // NCR: one byte of nothing
			if (app && index == 41) begin
				acmd41_tries = acmd41_tries + 1;
				if (acmd41_tries >= 2) idle = 0;
				send({7'd0, idle});
			end else case (index)
				0:  begin idle = 1; acmd41_tries = 0; send(8'h01); end
				8:  begin send({7'd0, idle}); send(8'h00); send(8'h00); send(8'h01); send(a[7:0]); end
				55: send({7'd0, idle});
				58: begin send({7'd0, idle}); send(8'hC0); send(8'hFF); send(8'h80); send(8'h00); end
				16: send({7'd0, idle});
				17: begin
					send(8'h00);
					send(8'hFF);
					send(8'hFE);
					for (k = 0; k < 512; k = k + 1)
						send(in_range(a) ? mem[(a - BASE) * 512 + k] : 8'h00);
					send(8'h12);                    // CRC (not checked by the host)
					send(8'h34);
					reads = reads + 1;
				end
				24: begin
					send(8'h00);
					wr_state = 1;
					wr_block = a;
				end
				default: begin
					send(8'h04);                    // illegal command
					errors = errors + 1;
				end
			endcase
			app = index == 55;
		end
	endtask

	task byte_in(input [7:0] b);
		integer k;
		begin
			if (wr_state == 1) begin
				if (b == 8'hFE) begin
					wr_state = 2;
					wr_count = 0;
				end
			end else if (wr_state == 2) begin
				if (wr_count < 512)
					wr_buf[wr_count] = b;
				wr_count = wr_count + 1;
				if (wr_count == 514) begin              // data and two CRC bytes
					if (in_range(wr_block))
						for (k = 0; k < 512; k = k + 1)
							mem[(wr_block - BASE) * 512 + k] = wr_buf[k];
					writes = writes + 1;
					send(8'hE5);                    // data accepted (xxx0_0101)
					send(8'h00);                    // busy
					send(8'h00);
					send(8'hFF);
					wr_state = 0;
				end
			end else if (cmd_len == 0) begin
				if (b[7:6] == 2'b01) begin
					cmd[0] = b;
					cmd_len = 1;
				end
			end else begin
				cmd[cmd_len] = b;
				cmd_len = cmd_len + 1;
				if (cmd_len == 6) begin
					cmd_len = 0;
					command;
				end
			end
		end
	endtask

	// --- SPI ----------------------------------------------------------------------------

	always @(posedge sck) if (!cs) begin
		in_byte = {in_byte[6:0], mosi};
		bits = bits + 1;
		if (bits == 8) begin
			bits = 0;
			byte_in(in_byte);
			if (q_head != q_tail) begin
				out_byte = q[q_head % 1024];
				q_head = q_head + 1;
			end else
				out_byte = 8'hFF;
		end
	end

	always @(negedge sck) if (!cs)
		miso <= out_byte[7 - bits];

	// deselected: the command collection starts over, an unread answer is
	// dropped, MISO floats (here: high)
	always @(posedge cs) begin
		bits = 0;
		cmd_len = 0;
		q_head = q_tail;
		out_byte = 8'hFF;
		miso <= 1'b1;
	end

endmodule
