// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier control unit: the multi-cycle state machine.
//
//   BOOT -> FETCH -> DECODE -> EXECUTE -> FETCH         (all others; a
//                                                         multiply/divide
//                                                         stays in EXECUTE
//                                                         until md_wait falls)
//                                 |
//                                 +-> MEM -> WB -> FETCH  (loads, stores)
//                                 +-> TRAP                (exception, until reset)
//
// An instruction commits at the end of EXECUTE, or of WB for loads and
// stores. On commit the PC and rd are written and the next fetch is
// requested in the same cycle. The bus is always idle by then, so
// back-to-back transfers still get their idle cycle in between.

`timescale 1 ns / 1 ps

module nt_control #(
	parameter ENABLE_DEBUG = 0
) (
	input      clk,
	input      resetn,
	input      debug_halt_request,
	input      debug_resume,
	input      debug_step,

	input      bus_done,
	input      is_mem,      // EXECUTE: the instruction is a load or store
	input      exception,   // EXECUTE: the instruction cannot complete
	input      md_wait,     // EXECUTE: the multiply/divide result is not there yet

	output     if_req,      // start an instruction fetch
	output     ir_we,       // fetched instruction arrives
	output     id_we,       // capture the ID/EX stage register
	output     ls_req,      // start the load/store bus access
	output     load_we,     // load data arrives
	output     commit,      // instruction completes: write PC and rd
	output     wb_load,     // the rd value comes from the load unit
	output     executing,   // in EXECUTE
	output     trap,
	output     halted
);
	generate
		if (ENABLE_DEBUG) begin : gen_debug
			localparam [2:0] S_BOOT    = 3'd0;
			localparam [2:0] S_FETCH   = 3'd1;
			localparam [2:0] S_DECODE  = 3'd2;
			localparam [2:0] S_EXECUTE = 3'd3;
			localparam [2:0] S_MEM     = 3'd4;
			localparam [2:0] S_WB      = 3'd5;
			localparam [2:0] S_TRAP    = 3'd6;
			localparam [2:0] S_HALTED  = 3'd7;

			reg [2:0] state;
			reg step_active;
			wire ex_done = state == S_EXECUTE && !exception &&
			               !is_mem && !md_wait;
			wire halt_after_commit = debug_halt_request || step_active;

			assign commit = ex_done || state == S_WB;
			assign ir_we = state == S_FETCH && bus_done;
			assign id_we = state == S_DECODE;
			assign ls_req = state == S_EXECUTE && !exception && is_mem;
			assign load_we = state == S_MEM && bus_done;
			assign wb_load = state == S_WB;
			assign if_req = (commit && !halt_after_commit) ||
			                (state == S_BOOT && !debug_halt_request);
			assign trap = state == S_TRAP;
			assign executing = state == S_EXECUTE;
			assign halted = state == S_HALTED || state == S_TRAP;

			always @(posedge clk) begin
				if (!resetn) begin
					state <= S_BOOT;
					step_active <= 1'b0;
				end else begin
					case (state)
						S_BOOT:    state <= debug_halt_request ? S_HALTED : S_FETCH;
						S_FETCH:   if (bus_done)
							state <= debug_halt_request ? S_HALTED : S_DECODE;
						S_DECODE:  state <= S_EXECUTE;
						S_EXECUTE: state <= exception ? S_TRAP :
						                    is_mem    ? S_MEM  :
						                    md_wait   ? S_EXECUTE :
						                    halt_after_commit ? S_HALTED : S_FETCH;
						S_MEM:     if (bus_done) state <= S_WB;
						S_WB:      state <= halt_after_commit ? S_HALTED : S_FETCH;
						S_HALTED:  if (debug_resume) begin
							step_active <= debug_step;
							state <= S_BOOT;
						end
						default:   state <= S_TRAP;
					endcase

					if (state == S_HALTED && debug_resume && !debug_step)
						step_active <= 1'b0;
					else if (state == S_EXECUTE && exception)
						step_active <= 1'b0;
					else if (state == S_EXECUTE && ex_done && halt_after_commit)
						step_active <= 1'b0;
					else if (state == S_WB && halt_after_commit)
						step_active <= 1'b0;
				end
			end
		end else begin : gen_normal
			localparam [2:0] S_BOOT    = 3'd0;
			localparam [2:0] S_FETCH   = 3'd1;
			localparam [2:0] S_DECODE  = 3'd2;
			localparam [2:0] S_EXECUTE = 3'd3;
			localparam [2:0] S_MEM     = 3'd4;
			localparam [2:0] S_WB      = 3'd5;
			localparam [2:0] S_TRAP    = 3'd6;

			reg [2:0] state;
			wire ex_done = state == S_EXECUTE && !exception &&
			               !is_mem && !md_wait;
			assign commit = ex_done || state == S_WB;
			assign ir_we = state == S_FETCH && bus_done;
			assign id_we = state == S_DECODE;
			assign ls_req = state == S_EXECUTE && !exception && is_mem;
			assign load_we = state == S_MEM && bus_done;
			assign wb_load = state == S_WB;
			assign if_req = commit || state == S_BOOT;
			assign trap = state == S_TRAP;
			assign executing = state == S_EXECUTE;
			assign halted = 1'b0;

			always @(posedge clk) begin
				if (!resetn) begin
					state <= S_BOOT;
				end else begin
					case (state)
						S_BOOT:    state <= S_FETCH;
						S_FETCH:   if (bus_done) state <= S_DECODE;
						S_DECODE:  state <= S_EXECUTE;
						S_EXECUTE: state <= exception ? S_TRAP :
						                    is_mem    ? S_MEM  :
						                    md_wait   ? S_EXECUTE : S_FETCH;
						S_MEM:     if (bus_done) state <= S_WB;
						S_WB:      state <= S_FETCH;
						default:   state <= S_TRAP;
					endcase
				end
			end
		end
	endgenerate

endmodule
