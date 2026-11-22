// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier decode stage.
//
// Decodes the instruction register, reads the register file and, on
// id_we, captures everything the later stages need in the ID/EX stage
// register (the id_* outputs). Those stay stable until the next
// instruction is decoded, so execute, memory and writeback all work
// from them.
//
// Supported: RV32I, FENCE/FENCE.I (no-ops), read-only access to the
// cycle/time/instret counters via CSRRS/CSRRC/CSRRSI/CSRRCI with a zero
// source. Everything else is flagged illegal. ECALL/EBREAK are flagged
// separately in id_sys_trap.

`timescale 1 ns / 1 ps

module nt_decode (
	input             clk,
	input             id_we,

	input      [31:0] ir,
	input      [31:0] pc,

	output     [ 4:0] rs1_addr,
	output     [ 4:0] rs2_addr,
	input      [31:0] rs1_data,
	input      [31:0] rs2_data,

	output reg [31:0] id_pc,
	output reg [31:0] id_rs1,
	output reg [31:0] id_rs2,
	output reg [31:0] id_imm,
	output reg [ 4:0] id_rd,
	output reg        id_rd_we,     // writes a non-zero rd
	output reg [ 3:0] id_alu_op,    // {alt, funct3}, see nt_alu
	output reg        id_alu_imm,   // ALU operand b is the immediate
	output reg [ 2:0] id_funct3,    // branch condition / memory access size
	output reg        id_lui,
	output reg        id_auipc,
	output reg        id_jal,
	output reg        id_jalr,
	output reg        id_branch,
	output reg        id_load,
	output reg        id_store,
	output reg        id_csr,       // counter read, address in id_imm[11:0]
	output reg        id_md,        // M extension: multiply / divide (funct3)
	output reg        id_sys_trap,  // ECALL or EBREAK
	output reg        id_illegal
);
	localparam [6:0] OPC_LUI    = 7'b0110111;
	localparam [6:0] OPC_AUIPC  = 7'b0010111;
	localparam [6:0] OPC_JAL    = 7'b1101111;
	localparam [6:0] OPC_JALR   = 7'b1100111;
	localparam [6:0] OPC_BRANCH = 7'b1100011;
	localparam [6:0] OPC_LOAD   = 7'b0000011;
	localparam [6:0] OPC_STORE  = 7'b0100011;
	localparam [6:0] OPC_OP_IMM = 7'b0010011;
	localparam [6:0] OPC_OP     = 7'b0110011;
	localparam [6:0] OPC_FENCE  = 7'b0001111;
	localparam [6:0] OPC_SYSTEM = 7'b1110011;

	wire [6:0] opcode = ir[6:0];
	wire [4:0] rd     = ir[11:7];
	wire [2:0] funct3 = ir[14:12];
	wire [6:0] funct7 = ir[31:25];

	assign rs1_addr = ir[19:15];
	assign rs2_addr = ir[24:20];

	wire [31:0] imm_i = {{21{ir[31]}}, ir[30:20]};
	wire [31:0] imm_s = {{21{ir[31]}}, ir[30:25], ir[11:7]};
	wire [31:0] imm_b = {{20{ir[31]}}, ir[7], ir[30:25], ir[11:8], 1'b0};
	wire [31:0] imm_u = {ir[31:12], 12'b0};
	wire [31:0] imm_j = {{12{ir[31]}}, ir[19:12], ir[20], ir[30:21], 1'b0};

	wire is_lui    = opcode == OPC_LUI;
	wire is_auipc  = opcode == OPC_AUIPC;
	wire is_jal    = opcode == OPC_JAL;
	wire is_jalr   = opcode == OPC_JALR;
	wire is_branch = opcode == OPC_BRANCH;
	wire is_load   = opcode == OPC_LOAD;
	wire is_store  = opcode == OPC_STORE;
	wire is_op_imm = opcode == OPC_OP_IMM;
	wire is_op     = opcode == OPC_OP;
	wire is_fence  = opcode == OPC_FENCE;
	wire is_system = opcode == OPC_SYSTEM;

	// funct7 is only allowed to be 0100000 for SUB/SRA(I)
	wire alt_ok      = funct3 == 3'b000 || funct3 == 3'b101;
	wire is_m        = funct7 == 7'b0000001;  // MUL ... REMU
	wire op_ok       = funct7 == 7'b0000000 || (funct7 == 7'b0100000 && alt_ok) || is_m;
	wire op_imm_ok   = funct3 == 3'b001 ? funct7 == 7'b0000000 :
	                   funct3 == 3'b101 ? funct7 == 7'b0000000 || funct7 == 7'b0100000 :
	                   1'b1;

	// ECALL/EBREAK; MRET, WFI and friends are not supported
	wire is_ecall_ebreak = is_system && funct3 == 3'b000 && rd == 5'd0 &&
	                       rs1_addr == 5'd0 && ir[31:21] == 11'd0;

	// The counters are read-only: only the CSRRS/CSRRC(I) forms with a
	// zero source, which never write the CSR, are accepted.
	wire is_csr_read = is_system && funct3[1] && rs1_addr == 5'd0;

	reg legal;
	always @* begin
		case (1'b1)
			is_lui, is_auipc, is_jal: legal = 1'b1;
			is_jalr:   legal = funct3 == 3'b000;
			is_branch: legal = funct3[2:1] != 2'b01;
			is_load:   legal = funct3 != 3'b011 && funct3[2:1] != 2'b11;
			is_store:  legal = funct3[2] == 1'b0 && funct3[1:0] != 2'b11;
			is_op_imm: legal = op_imm_ok;
			is_op:     legal = op_ok;
			is_fence:  legal = funct3[2:1] == 2'b00;
			is_system: legal = is_ecall_ebreak || is_csr_read;
			default:   legal = 1'b0;
		endcase
		if (ir[1:0] != 2'b11)
			legal = 1'b0;
	end

	reg [31:0] imm;
	always @* begin
		case (1'b1)
			is_lui, is_auipc: imm = imm_u;
			is_jal:           imm = imm_j;
			is_branch:        imm = imm_b;
			is_store:         imm = imm_s;
			default:          imm = imm_i;
		endcase
	end

	wire writes_rd = is_lui || is_auipc || is_jal || is_jalr || is_load ||
	                 is_op_imm || is_op || is_csr_read;

	// SUB/SRA select: funct7[5] for OP, only for shifts in OP-IMM (bit 30
	// is part of the immediate for ADDI etc.)
	wire alu_alt = ir[30] && (is_op || funct3 == 3'b101);

	always @(posedge clk) begin
		if (id_we) begin
			id_pc       <= pc;
			id_rs1      <= rs1_data;
			id_rs2      <= rs2_data;
			id_imm      <= imm;
			id_rd       <= rd;
			id_rd_we    <= legal && writes_rd && rd != 5'd0;
			id_alu_op   <= {alu_alt, funct3};
			id_alu_imm  <= is_op_imm;
			id_funct3   <= funct3;
			id_lui      <= is_lui;
			id_auipc    <= is_auipc;
			id_jal      <= is_jal;
			id_jalr     <= is_jalr;
			id_branch   <= is_branch;
			id_load     <= is_load;
			id_store    <= is_store;
			id_csr      <= is_csr_read;
			id_md       <= is_op && is_m;
			id_sys_trap <= is_ecall_ebreak;
			id_illegal  <= !legal;
		end
	end

endmodule
