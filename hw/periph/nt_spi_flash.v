// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier SPI flash controller: memory-mapped (execute-in-place) reads
// of a standard SPI NOR flash, plus a bit-bang mode for everything else
// (erase, program, ID read), all on two data lines (IO0 = MOSI, IO1 =
// MISO), as on the Tang Nano 9K.
//
// Memory port (XIP): 32-bit reads of the flash, word aligned. Writes are
// ignored. The controller keeps the flash read running after a word and
// prefetches the next word, so sequential code needs no new command or
// address.
//
//   single mode  03h read:              cmd, addr, data on IO0 / IO1
//   dual mode    BBh dual I/O read:     cmd on IO0, then address, mode
//                                       byte and data on IO1:IO0
//   dual + CRM   continuous read mode:  mode byte A5h, so the next read
//                                       starts directly with the address
//
// Config register:
//   bit 31     XIP_EN  1: memory-mapped reads, 0: bit-bang (reset: 1)
//   bit 22     DUAL    dual I/O reads (reset: 0)
//   bit 20     CRM     continuous read mode, needs DUAL (reset: 0)
//   bits 9:8   OE      bit-bang output enables for IO1, IO0
//   bit 5      CSB     bit-bang chip select
//   bit 4      CLK     bit-bang clock
//   bits 1:0   DO/DI   bit-bang IO1, IO0: write = output value,
//                      read = pin state
// Reads return the live pin states for bits 9:8, 5, 4 and 1:0.
//
// A write that leaves XIP_EN set restarts the read engine: it sends FFh
// FFh (leaves continuous read mode), then ABh (release from deep
// power-down) and waits POWERUP_CYCLES before the next read. A write that
// clears XIP_EN ends the running read and, if the flash is in continuous
// read mode, sends FFh FFh first; only then do the bit-bang values reach
// the pins. Config accesses wait (cfg_ready low) until that is done.
// `restart` pulses on every write that re-initialises the read engine (a
// read cache must forget what it holds then).

`timescale 1 ns / 1 ps

module nt_spi_flash #(
	parameter POWERUP_CYCLES = 1000      // >= tRES1 of the flash (40 us at 25 MHz)
) (
	input             clk,
	input             resetn,

	input             mem_valid,
	input      [23:0] mem_addr,
	input      [ 3:0] mem_wstrb,
	output            mem_ready,
	output     [31:0] mem_rdata,

	input             cfg_valid,
	input      [ 3:0] cfg_wstrb,
	input      [31:0] cfg_wdata,
	output            cfg_ready,
	output     [31:0] cfg_rdata,
	output            restart,          // pulse: the read engine re-initialises

	output            flash_csb,
	output            flash_clk,
	output            io0_oe,
	output            io0_do,
	input             io0_di,
	output            io1_oe,
	output            io1_do,
	input             io1_di
);
	// --- config register -------------------------------------------------------

	reg       xip_en, dual, crm;
	reg [1:0] bb_oe, bb_do;
	reg       bb_csb, bb_clk;

	wire cfg_write = cfg_valid && cfg_ready && |cfg_wstrb;
	wire new_xip_en = cfg_wstrb[3] ? cfg_wdata[31] : xip_en;

	assign restart = cfg_write && new_xip_en;

	always @(posedge clk) begin
		if (!resetn) begin
			xip_en <= 1'b1;
			dual   <= 1'b0;
			crm    <= 1'b0;
			bb_oe  <= 2'b00;
			bb_do  <= 2'b00;
			bb_csb <= 1'b1;
			bb_clk <= 1'b0;
		end else if (cfg_valid && cfg_ready) begin
			if (cfg_wstrb[0]) {bb_csb, bb_clk, bb_do} <= {cfg_wdata[5:4], cfg_wdata[1:0]};
			if (cfg_wstrb[1]) bb_oe <= cfg_wdata[9:8];
			if (cfg_wstrb[2]) {dual, crm} <= {cfg_wdata[22], cfg_wdata[20]};
			if (cfg_wstrb[3]) xip_en <= cfg_wdata[31];
		end
	end

	wire bb_active;   // the bit-bang values drive the pins
	assign cfg_ready = cfg_valid && (xip_en || bb_active);
	assign cfg_rdata = {xip_en, 8'd0, dual, 1'b0, crm, 10'd0, io1_oe, io0_oe,
	                    2'd0, flash_csb, flash_clk, 2'd0, io1_di, io0_di};

	// --- byte shifter (SPI mode 0, SCK = clk / 2) -------------------------------
	//
	// sh_start loads sh_tx and shifts one byte: 8 clocks on IO0/IO1 in
	// single mode, 4 clocks on IO1:IO0 in dual mode. In dual mode the pins
	// are driven unless sh_rx is set; sh_release drops the drivers as soon
	// as this byte is out (the flash turns the bus around after the mode
	// byte). Input is sampled at the rising SCK edge.

	reg        sh_start, sh_dual, sh_rx, sh_release;
	reg  [7:0] sh_tx;
	reg  [7:0] sh_out, sh_in;
	reg  [3:0] sh_left;
	reg        sck, sh_dual_q, sh_drive;

	wire sh_busy = sh_left != 4'd0;

	always @(posedge clk) begin
		if (!resetn) begin
			sh_left  <= 4'd0;
			sck      <= 1'b0;
			sh_drive <= 1'b0;
		end else if (sh_start) begin
			sh_out    <= sh_tx;
			sh_left   <= sh_dual ? 4'd4 : 4'd8;
			sh_dual_q <= sh_dual;
			sh_drive  <= !sh_rx;
		end else if (sh_busy) begin
			if (!sck) begin
				sck   <= 1'b1;
				sh_in <= sh_dual_q ? {sh_in[5:0], io1_di, io0_di} : {sh_in[6:0], io1_di};
			end else begin
				sck     <= 1'b0;
				sh_out  <= sh_dual_q ? {sh_out[5:0], 2'b00} : {sh_out[6:0], 1'b0};
				sh_left <= sh_left - 4'd1;
				if (sh_left == 4'd1 && sh_release)
					sh_drive <= 1'b0;
			end
		end
	end

	// --- read engine -----------------------------------------------------------

	localparam [3:0] E_CS_HIGH = 4'd0,   // deselect, wait, then go to `after_cs`
	                 E_WAKE_FF = 4'd1,   // FFh FFh: leave continuous read mode
	                 E_WAKE_AB = 4'd2,   // ABh: release from deep power-down
	                 E_IDLE    = 4'd3,   // no read running
	                 E_CMD     = 4'd4,   // read command
	                 E_ADDR    = 4'd5,   // 3 address bytes
	                 E_MODE    = 4'd6,   // mode byte (dual only)
	                 E_DATA    = 4'd7,   // 4 data bytes into nxt_data
	                 E_PAUSE   = 4'd8,   // word done: CS stays low, SCK stops
	                 E_EXIT    = 4'd9,   // XIP off: FFh FFh to leave continuous read mode
	                 E_OFF     = 4'd10;  // XIP off: pins belong to the bit-bang register

	reg  [3:0] state, after_cs;
	reg [15:0] wait_count;
	reg  [1:0] count;               // bytes sent / left in the current phase
	reg        csb;
	reg        crm_active;          // the flash expects an address without command

	// cur: the word served to the bus; nxt: the word being read from the
	// flash, which becomes cur when the CPU asks for it
	reg [23:0] cur_addr,  nxt_addr;
	reg [31:0] cur_data,  nxt_data;
	reg        cur_valid, nxt_valid;

	wire [23:0] req_addr  = {mem_addr[23:2], 2'b00};
	wire        req_read  = mem_valid && mem_wstrb == 4'd0 && xip_en && state != E_OFF;
	wire        cur_hit   = cur_valid && cur_addr == req_addr;
	wire        reading   = state == E_CMD || state == E_ADDR || state == E_MODE ||
	                        state == E_DATA || state == E_PAUSE;
	wire        nxt_hit   = reading && nxt_addr == req_addr;
	wire        miss      = req_read && !cur_hit && !nxt_hit;

	assign mem_ready = mem_valid && (mem_wstrb != 4'd0 || !xip_en || cur_hit);
	assign mem_rdata = cur_data;

	// the shifter has finished its byte and nothing new is queued
	wire byte_done = !sh_busy && !sh_start;

	task send(input [7:0] data, input is_dual, input is_rx, input drop_after);
		begin
			sh_tx      <= data;
			sh_dual    <= is_dual;
			sh_rx      <= is_rx;
			sh_release <= drop_after;
			sh_start   <= 1'b1;
		end
	endtask

	task deselect(input [3:0] next, input [15:0] cycles);
		begin
			state      <= E_CS_HIGH;
			after_cs   <= next;
			wait_count <= cycles;
			csb        <= 1'b1;
		end
	endtask

	always @(posedge clk) begin
		sh_start <= 1'b0;

		// after a reset the flash may still be in continuous read mode
		if (!resetn)
			crm_active <= 1'b1;

		if (!resetn || (cfg_write && new_xip_en)) begin
			// (re)start: wake the flash, forget everything read so far
			deselect(E_WAKE_FF, 16'd2);
			count      <= 2'd0;
			cur_valid  <= 1'b0;
			nxt_valid  <= 1'b0;
			sh_rx      <= 1'b0;
		end else if (cfg_write && state != E_OFF && state != E_EXIT) begin
			// XIP switched off: end the read, leave continuous read mode
			sh_start  <= 1'b0;
			cur_valid <= 1'b0;
			nxt_valid <= 1'b0;
			sh_rx     <= 1'b0;
			count     <= 2'd0;
			deselect(crm_active ? E_EXIT : E_OFF, 16'd2);
		end else begin
			// the CPU asks for the word that has been read ahead
			if (req_read && !cur_hit && nxt_valid && nxt_addr == req_addr) begin
				cur_addr  <= nxt_addr;
				cur_data  <= nxt_data;
				cur_valid <= 1'b1;
				nxt_valid <= 1'b0;
				nxt_addr  <= nxt_addr + 24'd4;
			end

			case (state)
				E_CS_HIGH:
					if (wait_count != 16'd0) begin
						wait_count <= wait_count - 16'd1;
					end else begin
						state <= after_cs;
						csb   <= after_cs == E_IDLE || after_cs == E_OFF;
					end

				E_WAKE_FF: if (byte_done) begin
					if (count == 2'd2) begin
						count      <= 2'd0;
						crm_active <= 1'b0;
						deselect(E_WAKE_AB, 16'd2);
					end else begin
						send(8'hFF, 1'b0, 1'b0, 1'b0);
						count <= count + 2'd1;
					end
				end

				E_WAKE_AB: if (byte_done) begin
					if (count == 2'd1)
						deselect(E_IDLE, POWERUP_CYCLES);
					else begin
						send(8'hAB, 1'b0, 1'b0, 1'b0);
						count <= 2'd1;
					end
				end

				E_IDLE: if (req_read && !cur_hit) begin
					nxt_addr <= req_addr;
					csb      <= 1'b0;
					count    <= 2'd2;
					state    <= crm_active ? E_ADDR : E_CMD;
				end

				E_CMD: if (byte_done) begin
					send(dual ? 8'hBB : 8'h03, 1'b0, 1'b0, 1'b0);
					state <= E_ADDR;
				end

				E_ADDR: if (byte_done) begin
					send(nxt_addr[count*8 +: 8], dual, 1'b0, 1'b0);
					count <= count - 2'd1;
					if (count == 2'd0) begin
						count <= 2'd0;
						state <= dual ? E_MODE : E_DATA;
					end
				end

				E_MODE: if (byte_done) begin
					// A5h keeps the flash in continuous read mode, FFh ends it
					send(crm ? 8'hA5 : 8'hFF, 1'b1, 1'b0, 1'b1);
					crm_active <= crm;
					count      <= 2'd0;
					state      <= E_DATA;
				end

				E_DATA: if (byte_done) begin
					// count = data bytes received so far; the first byte_done
					// here ends the address/mode byte, not a data byte
					if (sh_rx)
						nxt_data <= {sh_in, nxt_data[31:8]};
					if (sh_rx && count == 2'd3) begin
						nxt_valid <= 1'b1;
						sh_rx     <= 1'b0;
						state     <= E_PAUSE;
					end else begin
						if (sh_rx)
							count <= count + 2'd1;
						send(8'hFF, dual, 1'b1, 1'b0);
					end
					if (miss) begin
						// the CPU wants another word: give up this read
						sh_start  <= 1'b0;
						nxt_valid <= 1'b0;
						deselect(E_IDLE, 16'd2);
					end
				end

				E_PAUSE:
					if (miss) begin
						nxt_valid <= 1'b0;
						deselect(E_IDLE, 16'd2);
					end else if (!nxt_valid) begin
						// the word was taken: read ahead the next one
						count <= 2'd0;
						state <= E_DATA;
					end

				E_EXIT: if (byte_done) begin
					if (count == 2'd2) begin
						crm_active <= 1'b0;
						deselect(E_OFF, 16'd2);
					end else begin
						send(8'hFF, 1'b0, 1'b0, 1'b0);
						count <= count + 2'd1;
					end
				end

				E_OFF: csb <= 1'b1;

				default: deselect(E_IDLE, 16'd2);
			endcase
		end
	end

	// --- pins ------------------------------------------------------------------

	assign bb_active = state == E_OFF;

	wire xip_drive0 = sh_dual_q ? sh_drive : 1'b1;

	assign flash_csb = bb_active ? bb_csb   : csb;
	assign flash_clk = bb_active ? bb_clk   : sck;
	assign io0_oe    = bb_active ? bb_oe[0] : xip_drive0;
	assign io1_oe    = bb_active ? bb_oe[1] : sh_dual_q && sh_drive;
	assign io0_do    = bb_active ? bb_do[0] : sh_dual_q ? sh_out[6] : sh_out[7];
	assign io1_do    = bb_active ? bb_do[1] : sh_out[7];

endmodule
