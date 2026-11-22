// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Project-specific CPU debug registers accessed through the ECP5 user JTAG
// bridge. This is not a RISC-V Debug Module.

`timescale 1 ns / 1 ps

module nt_cpu_debug (
	input             clk,
	input             resetn,
	input             valid,
	input      [ 7:0] addr,
	input      [31:0] wdata,
	input      [ 3:0] wstrb,
	output            ready,
	output     [31:0] rdata,
	output            error,

	input             core_halted,
	input             core_trap,
	input      [31:0] core_pc,
	input      [31:0] core_reg_rdata,
	output reg        core_halt_request,
	output reg        core_resume,
	output reg        core_step,
	output reg        core_pc_we,
	output reg [31:0] core_pc_wdata,
	output reg [ 4:0] core_reg_addr,
	output reg        core_reg_we,
	output reg [31:0] core_reg_wdata,
	output reg        system_reset
);
	localparam [7:0] REG_CONTROL = 8'h80;
	localparam [7:0] REG_PC      = 8'h84;
	localparam [7:0] REG_GPR_SEL = 8'h88;
	localparam [7:0] REG_GPR     = 8'h8C;
	localparam [7:0] REG_RESET   = 8'h90;

	reg [4:0] gpr_select;
	wire write_req = valid && |wstrb;
	wire invalid_gpr = addr == REG_GPR_SEL && write_req &&
	                   (wdata[31:5] != 27'd0 || !wstrb[0]);
	wire invalid_step = addr == REG_CONTROL && write_req && wdata[2] &&
	                    (!core_halted || core_trap);
	wire invalid_resume = addr == REG_CONTROL && write_req && wdata[1] &&
	                      (!core_halted || core_trap);
	wire invalid_pc_write = addr == REG_PC && write_req &&
	                        (!core_halted ||
	                         (wstrb[0] && wdata[1:0] != 2'b00));
	wire invalid_gpr_write = addr == REG_GPR && write_req && !core_halted;
	wire invalid_write = write_req &&
	                     (invalid_gpr || invalid_step || invalid_resume ||
	                      invalid_pc_write || invalid_gpr_write);

	assign ready = valid;
	assign error = valid && (addr < REG_CONTROL || addr > REG_RESET ||
	                         addr[1:0] != 2'b00 || invalid_write);

	reg [31:0] read_value;
	always @* begin
		case (addr)
			REG_CONTROL: read_value = {29'd0, core_halt_request,
			                           core_trap, core_halted};
			REG_PC:      read_value = core_pc;
			REG_GPR_SEL: read_value = {27'd0, gpr_select};
			REG_GPR:     read_value = core_reg_rdata;
			REG_RESET:   read_value = {31'd0, system_reset};
			default:     read_value = 32'd0;
		endcase
	end
	assign rdata = read_value;

	wire [31:0] merged_pc = {
		wstrb[3] ? wdata[31:24] : core_pc[31:24],
		wstrb[2] ? wdata[23:16] : core_pc[23:16],
		wstrb[1] ? wdata[15:8]  : core_pc[15:8],
		wstrb[0] ? wdata[7:0]   : core_pc[7:0]
	};
	wire [31:0] merged_gpr = {
		wstrb[3] ? wdata[31:24] : core_reg_rdata[31:24],
		wstrb[2] ? wdata[23:16] : core_reg_rdata[23:16],
		wstrb[1] ? wdata[15:8]  : core_reg_rdata[15:8],
		wstrb[0] ? wdata[7:0]   : core_reg_rdata[7:0]
	};

	always @(posedge clk) begin
		if (!resetn) begin
			gpr_select <= 5'd0;
			core_halt_request <= 1'b0;
			core_resume <= 1'b0;
			core_step <= 1'b0;
			core_pc_we <= 1'b0;
			core_pc_wdata <= 32'd0;
			core_reg_addr <= 5'd0;
			core_reg_we <= 1'b0;
			core_reg_wdata <= 32'd0;
			system_reset <= 1'b0;
		end else begin
			core_resume <= 1'b0;
			core_step <= 1'b0;
			core_pc_we <= 1'b0;
			core_reg_we <= 1'b0;
			core_reg_addr <= gpr_select;

			if (valid && ready && !error && write_req) begin
				case (addr)
					REG_CONTROL: begin
						if (wstrb[0]) begin
							if (wdata[2]) begin
								core_halt_request <= 1'b0;
								core_resume <= 1'b1;
								core_step <= 1'b1;
							end else if (wdata[1]) begin
								core_halt_request <= 1'b0;
								core_resume <= 1'b1;
							end else begin
								core_halt_request <= wdata[0];
							end
						end
					end
					REG_PC: begin
						core_pc_wdata <= merged_pc;
						core_pc_we <= 1'b1;
					end
					REG_GPR_SEL: gpr_select <= wdata[4:0];
					REG_GPR: begin
						core_reg_addr <= gpr_select;
						core_reg_wdata <= merged_gpr;
						core_reg_we <= 1'b1;
					end
					REG_RESET: if (wstrb[0])
						system_reset <= wdata[0];
					default: begin
					end
				endcase
			end
		end
	end
endmodule
