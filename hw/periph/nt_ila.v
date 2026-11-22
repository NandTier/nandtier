// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier on-chip logic analyzer. Captures CPU bus activity into a
// circular buffer and exposes the buffer through a memory-mapped interface.

`timescale 1 ns / 1 ps

module nt_ila (
	input             clk,
	input             resetn,

	input             valid,
	input      [31:0] addr,
	input      [31:0] wdata,
	input      [ 3:0] wstrb,
	output            ready,
	output     [31:0] rdata,

	input             dbg_valid,
	input      [ 7:0] dbg_addr,
	input      [31:0] dbg_wdata,
	input      [ 3:0] dbg_wstrb,
	output            dbg_ready,
	output     [31:0] dbg_rdata,

	input             bus_valid,
	input             bus_ready,
	input      [31:0] bus_addr,
	input      [31:0] bus_wdata,
	input      [ 3:0] bus_wstrb,
	input      [31:0] bus_rdata,
	input             bus_instr,
	input             bus_trap
);
	localparam ADDR_BITS = 7;
	localparam DEPTH = 1 << ADDR_BITS;

	// One 72-bit word per sample: the 8 flag bits share the block RAM with
	// the address and data (two 36-bit-wide BSRAMs, which had 8 bits spare).
	// As a separate 1,024-bit register, the flags took about 1,000 flops and
	// a 128-way multiplexer, and the Tang Nano 9K no longer placed.
	reg [71:0] sample_mem [0:DEPTH-1];
	reg [63:0] sample_data_q;
	reg [7:0] sample_flags_q;
	reg [ADDR_BITS-1:0] write_ptr;
	reg [7:0] sample_count;
	reg [ADDR_BITS-1:0] read_index;
	reg [31:0] trigger_addr, trigger_mask;
	reg [7:0] post_count, post_remaining;
	reg trigger_enable, armed, done, triggered;

	wire is_write = |wstrb;
	wire [7:0] reg_addr = addr[7:0];
	wire use_debug = dbg_valid;
	wire req_valid = use_debug || valid;
	wire req_write = use_debug ? |dbg_wstrb : is_write;
	wire [7:0] req_addr = use_debug ? dbg_addr : reg_addr;
	wire [31:0] req_wdata = use_debug ? dbg_wdata : wdata;
	wire [3:0] req_wstrb = use_debug ? dbg_wstrb : wstrb;
	wire trigger_hit = trigger_enable && bus_valid && bus_ready &&
	                   (((bus_addr ^ trigger_addr) & trigger_mask) == 32'd0);
	wire [ADDR_BITS-1:0] oldest_ptr =
		(sample_count == DEPTH) ? write_ptr : {ADDR_BITS{1'b0}};
	wire [ADDR_BITS-1:0] sample_slot = oldest_ptr + read_index;
	wire sample_read = req_valid && !req_write &&
	                   req_addr >= 8'h14 && req_addr <= 8'h1C;
	reg sample_read_valid;
	wire req_ready = !sample_read || sample_read_valid;

	always @(posedge clk) begin
		if (!resetn) begin
			sample_read_valid <= 1'b0;
		end else if (!req_valid || !sample_read) begin
			sample_read_valid <= 1'b0;
		end else if (!sample_read_valid) begin
			{sample_flags_q, sample_data_q} <= sample_mem[sample_slot];
			sample_read_valid <= 1'b1;
		end else if (ready) begin
			sample_read_valid <= 1'b0;
		end
	end

	always @(posedge clk) begin
		if (!resetn) begin
			write_ptr     <= {ADDR_BITS{1'b0}};
			sample_count  <= 8'd0;
			read_index    <= {ADDR_BITS{1'b0}};
			trigger_addr  <= 32'd0;
			trigger_mask  <= 32'd0;
			post_count    <= 8'd0;
			post_remaining <= 8'd0;
			trigger_enable <= 1'b0;
			armed         <= 1'b0;
			done          <= 1'b0;
			triggered     <= 1'b0;
		end else begin
			if (req_valid && req_write && req_ready) begin
				case (req_addr)
					8'h00: begin
						if (req_wstrb[0]) begin
							trigger_enable <= req_wdata[1];
							if (req_wdata[0]) begin
								write_ptr      <= {ADDR_BITS{1'b0}};
								sample_count   <= 8'd0;
								post_remaining <= 8'd0;
								armed          <= 1'b1;
								done           <= 1'b0;
								triggered      <= 1'b0;
							end else begin
								armed <= 1'b0;
							end
						end
					end
					8'h04: begin
						if (req_wstrb[0]) trigger_addr[ 7: 0] <= req_wdata[ 7: 0];
						if (req_wstrb[1]) trigger_addr[15: 8] <= req_wdata[15: 8];
						if (req_wstrb[2]) trigger_addr[23:16] <= req_wdata[23:16];
						if (req_wstrb[3]) trigger_addr[31:24] <= req_wdata[31:24];
					end
					8'h08: begin
						if (req_wstrb[0]) trigger_mask[ 7: 0] <= req_wdata[ 7: 0];
						if (req_wstrb[1]) trigger_mask[15: 8] <= req_wdata[15: 8];
						if (req_wstrb[2]) trigger_mask[23:16] <= req_wdata[23:16];
						if (req_wstrb[3]) trigger_mask[31:24] <= req_wdata[31:24];
					end
					8'h0C: begin
						if (req_wstrb[0]) post_count <= req_wdata[7:0];
					end
					8'h10: begin
						if (req_wstrb[0]) read_index <= req_wdata[ADDR_BITS-1:0];
					end
					default: begin end
				endcase
			end

			if (armed && !(req_valid && req_write && req_ready && req_addr == 8'h00)) begin
				sample_mem[write_ptr] <= {
					bus_trap, bus_instr, bus_wstrb, bus_valid, bus_ready,
					(bus_wstrb != 4'd0) ? bus_wdata : bus_rdata,
					bus_addr
				};
				write_ptr <= write_ptr + 1'b1;
				if (sample_count < DEPTH)
					sample_count <= sample_count + 1'b1;

				if (trigger_enable && !triggered && trigger_hit) begin
					triggered <= 1'b1;
					post_remaining <= post_count;
					if (post_count == 8'd0) begin
						armed <= 1'b0;
						done  <= 1'b1;
					end
				end else if (triggered) begin
					if (post_remaining <= 8'd1) begin
						armed <= 1'b0;
						done  <= 1'b1;
						post_remaining <= 8'd0;
					end else begin
						post_remaining <= post_remaining - 1'b1;
					end
				end else if (!trigger_enable && sample_count == DEPTH - 1) begin
					armed <= 1'b0;
					done  <= 1'b1;
				end
			end
		end
	end

	assign ready = valid && !use_debug && req_ready;
	assign dbg_ready = dbg_valid && use_debug && req_ready;
	wire [31:0] req_rdata = (req_addr == 8'h00) ?
	               {16'd0, sample_count, 5'd0, triggered, done, armed} :
	               (req_addr == 8'h04) ? trigger_addr :
	               (req_addr == 8'h08) ? trigger_mask :
	               (req_addr == 8'h0C) ? {24'd0, post_count} :
	               (req_addr == 8'h10) ? {{(32-ADDR_BITS){1'b0}}, read_index} :
	               (req_addr == 8'h14) ? sample_data_q[31:0] :
	               (req_addr == 8'h18) ? sample_data_q[63:32] :
	               (req_addr == 8'h1C) ? {24'd0, sample_flags_q} : 32'd0;
	assign rdata = req_rdata;
	assign dbg_rdata = req_rdata;

endmodule
