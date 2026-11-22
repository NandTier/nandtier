// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier -- a small multi-cycle RISC-V (RV32IM) processor core.
//
// Each instruction goes through the stages below, one at a time:
//
//   FETCH    nt_fetch    PC and instruction register, fetch over nt_bus
//   DECODE   nt_decode   decode, register file read, ID/EX stage register
//   EXECUTE  nt_execute  ALU, branch compare, address/target adder;
//            nt_muldiv   multiply / divide (M extension)
//   MEM      nt_lsu      load/store bus access (loads and stores only)
//   WB                   register file write (in EXECUTE for non-loads)
//
// nt_control sequences the stages, nt_bus owns the memory port, nt_csr
// holds the cycle/instret counters.
//
// Cycles per instruction, with a slave answering one cycle after valid:
// 4 for ALU ops, jumps and branches, 7 for loads and stores, 5 for
// multiplies, 38 for divides.
//
// Illegal instructions, ECALL/EBREAK, misaligned loads/stores/jump
// targets and writes to the (read-only) counters raise trap and halt the
// core until reset. A separate debug port can halt, step, and inspect the
// core without changing its normal memory interface. There are no interrupts.
//
// Memory interface: mem_valid stays high until mem_ready, address and
// data are stable meanwhile; mem_addr is word aligned, mem_wstrb is zero
// for reads; mem_instr marks instruction fetches.

`timescale 1 ns / 1 ps

module nandtier_core #(
	parameter [31:0] PROGADDR_RESET = 32'h0000_0000,
	parameter        ENABLE_CPU_DEBUG = 0
) (
	input             clk,
	input             resetn,
	input             debug_halt_request,
	input             debug_resume,
	input             debug_step,
	input             debug_pc_we,
	input      [31:0] debug_pc_wdata,
	input      [ 4:0] debug_reg_addr,
	input             debug_reg_we,
	input      [31:0] debug_reg_wdata,
	output            trap,
	output            debug_halted,
	output     [31:0] debug_pc,
	output     [31:0] debug_reg_rdata,

	output            mem_valid,
	output            mem_instr,
	input             mem_ready,
	output     [31:0] mem_addr,
	output     [31:0] mem_wdata,
	output     [ 3:0] mem_wstrb,
	input      [31:0] mem_rdata
);
	// control
	wire        if_req, ir_we, id_we, ls_req, load_we, commit, wb_load;
	wire        bus_done;
	wire [31:0] bus_rdata;
	wire        core_halted;
	wire        effective_halt_request = ENABLE_CPU_DEBUG && debug_halt_request;
	wire        effective_resume = ENABLE_CPU_DEBUG && debug_resume;
	wire        effective_step = ENABLE_CPU_DEBUG && debug_step;

	// fetch
	wire [31:0] pc, ir, fetch_addr;

	// decode / register file
	wire [ 4:0] rs1_addr, rs2_addr;
	wire [31:0] rs1_data, rs2_data;
	wire [ 4:0] rf_rs1_addr = debug_halted ? debug_reg_addr : rs1_addr;
	wire [31:0] id_pc, id_rs1, id_rs2, id_imm;
	wire [ 4:0] id_rd;
	wire [ 3:0] id_alu_op;
	wire [ 2:0] id_funct3;
	wire        id_rd_we, id_alu_imm, id_lui, id_auipc, id_jal, id_jalr;
	wire        id_branch, id_load, id_store, id_csr, id_sys_trap, id_illegal, id_md;

	// execute
	wire [31:0] ex_result, alu_result, next_pc, agu;
	wire [31:0] md_y;
	wire        md_done;
	wire        in_execute;
	wire        jump_misaligned;
	wire [31:0] csr_rdata;
	wire        csr_valid;

	// memory
	wire [31:0] ls_addr, ls_wdata, load_data;
	wire [ 3:0] ls_wstrb;
	wire        mem_misaligned;

	wire is_mem    = id_load || id_store;
	wire exception = id_illegal || id_sys_trap || jump_misaligned ||
	                 (is_mem && mem_misaligned) || (id_csr && !csr_valid);

	nt_control #(
		.ENABLE_DEBUG(ENABLE_CPU_DEBUG)
	) u_control (
		.clk      (clk),
		.resetn   (resetn),
		.bus_done (bus_done),
		.is_mem   (is_mem),
		.exception(exception),
		.md_wait  (id_md && !md_done),
		.debug_halt_request(effective_halt_request),
		.debug_resume(effective_resume),
		.debug_step(effective_step),
		.if_req   (if_req),
		.ir_we    (ir_we),
		.id_we    (id_we),
		.ls_req   (ls_req),
		.load_we  (load_we),
		.commit   (commit),
		.wb_load  (wb_load),
		.executing(in_execute),
		.trap     (trap),
		.halted   (core_halted)
	);

	nt_fetch #(
		.RESET_PC(PROGADDR_RESET)
	) u_fetch (
		.clk       (clk),
		.resetn    (resetn),
		.pc_we     (commit),
		.next_pc   (next_pc),
		.debug_pc_we(ENABLE_CPU_DEBUG && debug_pc_we),
		.debug_pc(debug_pc_wdata),
		.fetch_addr(fetch_addr),
		.ir_we     (ir_we),
		.ir_in     (bus_rdata),
		.pc        (pc),
		.ir        (ir)
	);

	nt_decode u_decode (
		.clk        (clk),
		.id_we      (id_we),
		.ir         (ir),
		.pc         (pc),
		.rs1_addr   (rs1_addr),
		.rs2_addr   (rs2_addr),
		.rs1_data   (rs1_data),
		.rs2_data   (rs2_data),
		.id_pc      (id_pc),
		.id_rs1     (id_rs1),
		.id_rs2     (id_rs2),
		.id_imm     (id_imm),
		.id_rd      (id_rd),
		.id_rd_we   (id_rd_we),
		.id_alu_op  (id_alu_op),
		.id_alu_imm (id_alu_imm),
		.id_funct3  (id_funct3),
		.id_lui     (id_lui),
		.id_auipc   (id_auipc),
		.id_jal     (id_jal),
		.id_jalr    (id_jalr),
		.id_branch  (id_branch),
		.id_load    (id_load),
		.id_store   (id_store),
		.id_csr     (id_csr),
		.id_sys_trap(id_sys_trap),
		.id_illegal (id_illegal),
		.id_md      (id_md)
	);

	// writeback: loads write in WB, everything else at the end of EXECUTE
	nt_regfile u_regfile (
		.clk   (clk),
		.raddr1(rf_rs1_addr),
		.rdata1(rs1_data),
		.raddr2(rs2_addr),
		.rdata2(rs2_data),
		.we    (commit && id_rd_we),
		.waddr (id_rd),
		.wdata (wb_load ? load_data : ex_result),
		.debug_we(ENABLE_CPU_DEBUG && debug_reg_we),
		.debug_waddr(debug_reg_addr),
		.debug_wdata(debug_reg_wdata)
	);

	assign debug_halted = ENABLE_CPU_DEBUG && core_halted;
	assign debug_pc = pc;
	assign debug_reg_rdata = debug_halted ? rs1_data : 32'd0;

	nt_execute u_execute (
		.id_pc          (id_pc),
		.id_rs1         (id_rs1),
		.id_rs2         (id_rs2),
		.id_imm         (id_imm),
		.id_alu_op      (id_alu_op),
		.id_alu_imm     (id_alu_imm),
		.id_funct3      (id_funct3),
		.id_lui         (id_lui),
		.id_auipc       (id_auipc),
		.id_jal         (id_jal),
		.id_jalr        (id_jalr),
		.id_branch      (id_branch),
		.id_load        (id_load),
		.id_store       (id_store),
		.id_csr         (id_csr),
		.csr_rdata      (csr_rdata),
		.result         (alu_result),
		.next_pc        (next_pc),
		.agu            (agu),
		.jump_misaligned(jump_misaligned)
	);

	// M extension; EXECUTE holds until it is done
	nt_muldiv u_muldiv (
		.clk   (clk),
		.resetn(resetn),
		.go    (in_execute && id_md && !exception),
		.funct3(id_funct3),
		.a     (id_rs1),
		.b     (id_rs2),
		.done  (md_done),
		.y     (md_y)
	);

	assign ex_result = id_md ? md_y : alu_result;

	nt_csr u_csr (
		.clk   (clk),
		.resetn(resetn),
		.retire(commit),
		.addr  (id_imm[11:0]),
		.rdata (csr_rdata),
		.valid (csr_valid)
	);

	nt_lsu u_lsu (
		.clk       (clk),
		.funct3    (id_funct3),
		.is_store  (id_store),
		.addr      (agu),
		.store_data(id_rs2),
		.misaligned(mem_misaligned),
		.bus_addr  (ls_addr),
		.bus_wdata (ls_wdata),
		.bus_wstrb (ls_wstrb),
		.load_we   (load_we),
		.bus_rdata (bus_rdata),
		.load_data (load_data)
	);

	nt_bus u_bus (
		.clk      (clk),
		.resetn   (resetn),
		.if_req   (if_req),
		.if_addr  (fetch_addr),
		.ls_req   (ls_req),
		.ls_addr  (ls_addr),
		.ls_wdata (ls_wdata),
		.ls_wstrb (ls_wstrb),
		.done     (bus_done),
		.rdata    (bus_rdata),
		.mem_valid(mem_valid),
		.mem_instr(mem_instr),
		.mem_ready(mem_ready),
		.mem_addr (mem_addr),
		.mem_wdata(mem_wdata),
		.mem_wstrb(mem_wstrb),
		.mem_rdata(mem_rdata)
	);

endmodule
