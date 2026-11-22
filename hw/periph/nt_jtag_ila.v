// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// ECP5 user-chain transport for NandTier ILA and CPU debug access.

`timescale 1 ns / 1 ps

module nt_jtag_ila_bridge (
	input             clk_sys,
	input             resetn_sys,

	input             jtag_clk,
	input             jtag_resetn,
	input             jtag_tdi,
	input             jtag_shift,
	input             jtag_update,
	input             jtag_chain1,
	output            jtag_tdo,

	output reg        ila_valid,
	output reg [ 7:0] ila_addr,
	output reg [31:0] ila_wdata,
	output reg [ 3:0] ila_wstrb,
	input             ila_ready,
	input      [31:0] ila_rdata,
	output reg        cpu_valid,
	output reg [ 7:0] cpu_addr,
	output reg [31:0] cpu_wdata,
	output reg [ 3:0] cpu_wstrb,
	input             cpu_ready,
	input      [31:0] cpu_rdata,
	input             cpu_error
);
	reg [63:0] shift_reg;
	reg [63:0] command_mailbox;
	reg [63:0] response_mailbox;
	reg [63:0] response_hold;
	reg        request_toggle;
	reg        acknowledge_toggle;
	reg [1:0]  request_sync;
	reg [1:0]  acknowledge_sync;
	reg        request_seen;
	reg        acknowledge_seen;
	reg [3:0]  active_op;
	reg [7:0]  active_seq;
	reg        command_active;
	reg        active_cpu;

	wire [3:0] command_op = shift_reg[63:60];
	wire command_op_valid = command_op == 4'h1 || command_op == 4'h2;

	assign jtag_tdo = shift_reg[0];

	always @(posedge jtag_clk or negedge jtag_resetn) begin
		if (!jtag_resetn) begin
			shift_reg <= 64'd0;
			command_mailbox <= 64'd0;
			request_toggle <= 1'b0;
			acknowledge_sync <= 2'b00;
			acknowledge_seen <= 1'b0;
			response_hold <= 64'd0;
		end else begin
			acknowledge_sync <= {acknowledge_sync[0], acknowledge_toggle};
			if (acknowledge_sync[1] != acknowledge_seen) begin
				acknowledge_seen <= acknowledge_sync[1];
				response_hold <= response_mailbox;
			end

			if (jtag_chain1 && !jtag_shift)
				shift_reg <= response_hold;
			else if (jtag_chain1 && jtag_shift)
				shift_reg <= {jtag_tdi, shift_reg[63:1]};

			if (jtag_chain1 && jtag_update && command_op_valid &&
			    request_toggle == acknowledge_sync[1]) begin
				command_mailbox <= shift_reg;
				request_toggle <= !request_toggle;
			end
		end
	end

	always @(posedge clk_sys) begin
		if (!resetn_sys) begin
			request_sync <= 2'b00;
			request_seen <= 1'b0;
			acknowledge_toggle <= 1'b0;
			response_mailbox <= 64'd0;
			ila_valid <= 1'b0;
			ila_addr <= 8'd0;
			ila_wdata <= 32'd0;
			ila_wstrb <= 4'd0;
			cpu_valid <= 1'b0;
			cpu_addr <= 8'd0;
			cpu_wdata <= 32'd0;
			cpu_wstrb <= 4'd0;
			active_op <= 4'd0;
			active_seq <= 8'd0;
			command_active <= 1'b0;
			active_cpu <= 1'b0;
		end else begin
			request_sync <= {request_sync[0], request_toggle};

			if (!command_active && request_sync[1] != request_seen) begin
				request_seen <= request_sync[1];
				active_op <= command_mailbox[63:60];
				active_seq <= command_mailbox[51:44];
				ila_addr <= command_mailbox[59:52];
				ila_wdata <= command_mailbox[31:0];
				cpu_addr <= command_mailbox[59:52];
				cpu_wdata <= command_mailbox[31:0];
				if ((command_mailbox[63:60] == 4'h1 ||
				     command_mailbox[63:60] == 4'h2) &&
				    command_mailbox[53:52] == 2'b00 &&
				    ((command_mailbox[59:52] <= 8'h1C) ||
				     (command_mailbox[59:52] >= 8'h80 &&
				      command_mailbox[59:52] <= 8'h90))) begin
					active_cpu <= command_mailbox[59:52] >= 8'h80;
					if (command_mailbox[59:52] >= 8'h80) begin
						cpu_wstrb <= command_mailbox[63:60] == 4'h1 ?
						             4'hF : 4'h0;
						cpu_valid <= 1'b1;
					end else begin
						ila_wstrb <= command_mailbox[63:60] == 4'h1 ?
						             4'hF : 4'h0;
						ila_valid <= 1'b1;
					end
					command_active <= 1'b1;
				end else begin
					response_mailbox <= {
						4'h2, command_mailbox[51:44], 20'd0, 32'd0
					};
					acknowledge_toggle <= request_sync[1];
				end
			end else if (command_active &&
			             (active_cpu ? cpu_ready : ila_ready)) begin
				if (active_cpu && cpu_error) begin
					response_mailbox <= {
						4'h2, active_seq, 20'd0, 32'd0
					};
				end else begin
					response_mailbox <= {
						4'h0, active_seq, 20'd0,
						(active_op == 4'h2) ?
						(active_cpu ? cpu_rdata : ila_rdata) : 32'd0
					};
				end
				acknowledge_toggle <= request_seen;
				ila_valid <= 1'b0;
				ila_wstrb <= 4'd0;
				cpu_valid <= 1'b0;
				cpu_wstrb <= 4'd0;
				command_active <= 1'b0;
			end
		end
	end
endmodule

module nt_ecp5_jtag_ila (
	input             clk_sys,
	input             resetn_sys,
	output            ila_valid,
	output     [ 7:0] ila_addr,
	output     [31:0] ila_wdata,
	output     [ 3:0] ila_wstrb,
	input             ila_ready,
	input      [31:0] ila_rdata,
	output            cpu_valid,
	output     [ 7:0] cpu_addr,
	output     [31:0] cpu_wdata,
	output     [ 3:0] cpu_wstrb,
	input             cpu_ready,
	input      [31:0] cpu_rdata,
	input             cpu_error
);
	wire jtck, jtdi, jshift, jupdate, jrstn, jce1;
	wire jtdo1;
	wire jtag_resetn = jrstn && resetn_sys;

	JTAGG u_jtag (
		.TCK   (),
		.TMS   (),
		.TDI   (),
		.JTDO2 (jtdo1),
		.JTDO1 (jtdo1),
		.TDO   (),
		.JTDI  (jtdi),
		.JTCK  (jtck),
		.JRTI2 (),
		.JRTI1 (),
		.JSHIFT(jshift),
		.JUPDATE(jupdate),
		.JRSTN (jrstn),
		.JCE2  (),
		.JCE1  (jce1)
	);

	nt_jtag_ila_bridge u_bridge (
		.clk_sys(clk_sys),
		.resetn_sys(resetn_sys),
		.jtag_clk(~jtck),
		.jtag_resetn(jtag_resetn),
		.jtag_tdi(jtdi),
		.jtag_shift(jshift),
		.jtag_update(jupdate),
		.jtag_chain1(jce1),
		.jtag_tdo(jtdo1),
		.ila_valid(ila_valid),
		.ila_addr(ila_addr),
		.ila_wdata(ila_wdata),
		.ila_wstrb(ila_wstrb),
		.ila_ready(ila_ready),
		.ila_rdata(ila_rdata),
		.cpu_valid(cpu_valid),
		.cpu_addr(cpu_addr),
		.cpu_wdata(cpu_wdata),
		.cpu_wstrb(cpu_wstrb),
		.cpu_ready(cpu_ready),
		.cpu_rdata(cpu_rdata),
		.cpu_error(cpu_error)
	);
endmodule
