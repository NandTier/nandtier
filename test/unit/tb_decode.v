// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_decode:
//  1. legality of random and opcode-targeted instruction words against
//     the MATCH/MASK table of the supported instructions (as listed in
//     riscv-opcodes);
//  2. register fields, immediates and control outputs of every
//     supported instruction class with random fields.

`timescale 1 ns / 1 ps

module tb_decode;

	reg         clk = 0;
	reg  [31:0] ir, pc;
	reg  [31:0] rs1_data, rs2_data;

	wire [ 4:0] rs1_addr, rs2_addr;
	wire [31:0] id_pc, id_rs1, id_rs2, id_imm;
	wire [ 4:0] id_rd;
	wire [ 3:0] id_alu_op;
	wire [ 2:0] id_funct3;
	wire        id_rd_we, id_alu_imm, id_lui, id_auipc, id_jal, id_jalr;
	wire        id_branch, id_load, id_store, id_csr, id_sys_trap, id_illegal, id_md;

	nt_decode dut (
		.clk(clk), .id_we(1'b1), .ir(ir), .pc(pc),
		.rs1_addr(rs1_addr), .rs2_addr(rs2_addr), .rs1_data(rs1_data), .rs2_data(rs2_data),
		.id_pc(id_pc), .id_rs1(id_rs1), .id_rs2(id_rs2), .id_imm(id_imm), .id_rd(id_rd),
		.id_rd_we(id_rd_we), .id_alu_op(id_alu_op), .id_alu_imm(id_alu_imm), .id_funct3(id_funct3),
		.id_lui(id_lui), .id_auipc(id_auipc), .id_jal(id_jal), .id_jalr(id_jalr),
		.id_branch(id_branch), .id_load(id_load), .id_store(id_store), .id_csr(id_csr),
		.id_sys_trap(id_sys_trap), .id_illegal(id_illegal), .id_md(id_md)
	);

	task step;
		begin
			#4 clk = 1;
			#5 clk = 0;
			#1;
		end
	endtask

	// --- 1. legality ---------------------------------------------------------

	localparam N_PAT = 46;
	reg [31:0] match [0:N_PAT-1];
	reg [31:0] mask  [0:N_PAT-1];
	integer np = 0;

	task pat(input [31:0] m, input [31:0] k);
		begin
			match[np] = m;
			mask[np]  = k;
			np = np + 1;
		end
	endtask

	initial begin
		pat(32'h0000_0037, 32'h0000_007f);  // lui
		pat(32'h0000_0017, 32'h0000_007f);  // auipc
		pat(32'h0000_006f, 32'h0000_007f);  // jal
		pat(32'h0000_0067, 32'h0000_707f);  // jalr
		pat(32'h0000_0063, 32'h0000_707f);  // beq
		pat(32'h0000_1063, 32'h0000_707f);  // bne
		pat(32'h0000_4063, 32'h0000_707f);  // blt
		pat(32'h0000_5063, 32'h0000_707f);  // bge
		pat(32'h0000_6063, 32'h0000_707f);  // bltu
		pat(32'h0000_7063, 32'h0000_707f);  // bgeu
		pat(32'h0000_0003, 32'h0000_707f);  // lb
		pat(32'h0000_1003, 32'h0000_707f);  // lh
		pat(32'h0000_2003, 32'h0000_707f);  // lw
		pat(32'h0000_4003, 32'h0000_707f);  // lbu
		pat(32'h0000_5003, 32'h0000_707f);  // lhu
		pat(32'h0000_0023, 32'h0000_707f);  // sb
		pat(32'h0000_1023, 32'h0000_707f);  // sh
		pat(32'h0000_2023, 32'h0000_707f);  // sw
		pat(32'h0000_0013, 32'h0000_707f);  // addi
		pat(32'h0000_2013, 32'h0000_707f);  // slti
		pat(32'h0000_3013, 32'h0000_707f);  // sltiu
		pat(32'h0000_4013, 32'h0000_707f);  // xori
		pat(32'h0000_6013, 32'h0000_707f);  // ori
		pat(32'h0000_7013, 32'h0000_707f);  // andi
		pat(32'h0000_1013, 32'hfe00_707f);  // slli
		pat(32'h0000_5013, 32'hfe00_707f);  // srli
		pat(32'h4000_5013, 32'hfe00_707f);  // srai
		pat(32'h0000_0033, 32'hfe00_707f);  // add
		pat(32'h4000_0033, 32'hfe00_707f);  // sub
		pat(32'h0000_1033, 32'hfe00_707f);  // sll
		pat(32'h0000_2033, 32'hfe00_707f);  // slt
		pat(32'h0000_3033, 32'hfe00_707f);  // sltu
		pat(32'h0000_4033, 32'hfe00_707f);  // xor
		pat(32'h0000_5033, 32'hfe00_707f);  // srl
		pat(32'h4000_5033, 32'hfe00_707f);  // sra
		pat(32'h0000_6033, 32'hfe00_707f);  // or
		pat(32'h0000_7033, 32'hfe00_707f);  // and
		pat(32'h0200_0033, 32'hfe00_007f);  // M extension: mul ... remu
		pat(32'h0000_000f, 32'h0000_707f);  // fence
		pat(32'h0000_100f, 32'h0000_707f);  // fence.i
		pat(32'h0000_0073, 32'hffff_ffff);  // ecall
		pat(32'h0010_0073, 32'hffff_ffff);  // ebreak
		pat(32'h0000_2073, 32'h000f_f07f);  // csrrs  rd, csr, x0
		pat(32'h0000_3073, 32'h000f_f07f);  // csrrc  rd, csr, x0
		pat(32'h0000_6073, 32'h000f_f07f);  // csrrsi rd, csr, 0
		pat(32'h0000_7073, 32'h000f_f07f);  // csrrci rd, csr, 0
	end

	function is_legal(input [31:0] insn);
		integer p;
		begin
			is_legal = 0;
			for (p = 0; p < N_PAT; p = p + 1)
				if ((insn & mask[p]) == match[p])
					is_legal = 1;
		end
	endfunction

	localparam [7*11-1:0] OPCODES = {7'h37, 7'h17, 7'h6f, 7'h67, 7'h63, 7'h03, 7'h23,
	                                 7'h13, 7'h33, 7'h0f, 7'h73};

	integer errors = 0, checks = 0, legal_seen = 0;
	integer i;

	task fail(input [8*40-1:0] what);
		begin
			errors = errors + 1;
			if (errors <= 20)
				$display("  ir=%08x: %0s", ir, what);
		end
	endtask

	task check_legality;
		begin
			step;
			checks = checks + 1;
			if (id_illegal !== !is_legal(ir))
				fail(is_legal(ir) ? "legal instruction flagged illegal" : "illegal instruction accepted");
			if (is_legal(ir) && id_md !== (ir[6:0] == 7'h33 && ir[31:25] == 7'b0000001))
				fail("M extension flag wrong");
			if (is_legal(ir))
				legal_seen = legal_seen + 1;
			if (id_sys_trap !== (ir == 32'h0000_0073 || ir == 32'h0010_0073))
				fail("id_sys_trap");
		end
	endtask

	// --- 2. fields and controls ---------------------------------------------

	reg [4:0]  rd, rs1, rs2;
	reg [31:0] imm;

	task expect_ctrl(input [8*8-1:0] cls, input [31:0] exp_imm, input exp_writes_rd,
	                 input [3:0] exp_alu_op, input exp_alu_imm);
		begin
			step;
			checks = checks + 1;
			if (id_illegal)                     fail({cls, ": flagged illegal"});
			if (rs1_addr !== ir[19:15] || rs2_addr !== ir[24:20]) fail({cls, ": rs addr"});
			if (id_rs1 !== rs1_data || id_rs2 !== rs2_data)       fail({cls, ": rs data"});
			if (id_pc !== pc)                   fail({cls, ": pc"});
			if (id_rd !== rd)                   fail({cls, ": rd"});
			if (id_imm !== exp_imm)             fail({cls, ": imm"});
			if (id_rd_we !== (exp_writes_rd && rd != 0)) fail({cls, ": rd_we"});
			if (id_funct3 !== ir[14:12])        fail({cls, ": funct3"});
			if (exp_alu_op !== 4'bxxxx && (id_alu_op !== exp_alu_op || id_alu_imm !== exp_alu_imm))
				fail({cls, ": alu op"});
			if ({id_lui, id_auipc, id_jal, id_jalr, id_branch, id_load, id_store, id_csr} !==
			    {cls == "lui", cls == "auipc", cls == "jal", cls == "jalr",
			     cls == "branch", cls == "load", cls == "store", cls == "csr"})
				fail({cls, ": class flags"});
		end
	endtask

	integer f;

	initial begin
		pc = 32'h8000_0000;
		rs1_data = 32'h1111_1111;
		rs2_data = 32'h2222_2222;

		// 1. random words, and random words with a valid major opcode
		for (i = 0; i < 20000; i = i + 1) begin
			ir = $random;
			check_legality;
			ir[6:0] = OPCODES[7 * ({$random} % 11) +: 7];
			check_legality;
			if (i % 4 == 0) begin
				ir[31:25] = i % 8 == 0 ? 7'b0100000 : i % 8 == 4 ? 7'b0000001 : 7'b0000000;
				check_legality;
			end
			if (i % 16 == 0) begin
				ir = {12'h000, 5'd0, 3'b000, 5'd0, 7'h73} | (i % 32 == 0 ? 32'h0010_0000 : 0);
				check_legality;
				ir = {$random} & 32'hfff0_7fff | 32'h0000_2073;
				check_legality;
			end
		end
		if (legal_seen < 5000)
			fail("too few legal instructions generated");

		// 2. per class
		for (i = 0; i < 2000; i = i + 1) begin
			rd = $random; rs1 = $random; rs2 = $random; imm = $random;
			pc = {$random} & 32'hffff_fffc;
			rs1_data = $random;
			rs2_data = $random;

			ir = {imm[31:12], rd, 7'h37};
			expect_ctrl("lui", {imm[31:12], 12'b0}, 1, 4'bxxxx, 0);
			ir = {imm[31:12], rd, 7'h17};
			expect_ctrl("auipc", {imm[31:12], 12'b0}, 1, 4'bxxxx, 0);
			ir = {imm[20], imm[10:1], imm[11], imm[19:12], rd, 7'h6f};
			expect_ctrl("jal", {{12{imm[20]}}, imm[19:1], 1'b0}, 1, 4'bxxxx, 0);
			ir = {imm[11:0], rs1, 3'b000, rd, 7'h67};
			expect_ctrl("jalr", {{21{imm[11]}}, imm[10:0]}, 1, 4'bxxxx, 0);

			f = {$random} % 6;
			f = f < 2 ? f : f + 2;
			ir = {imm[12], imm[10:5], rs2, rs1, f[2:0], imm[4:1], imm[11], 7'h63};
			rd = ir[11:7];
			expect_ctrl("branch", {{20{imm[12]}}, imm[11:1], 1'b0}, 0, 4'bxxxx, 0);

			f = {$random} % 5;
			f = f < 3 ? f : f + 1;
			rd = $random;
			ir = {imm[11:0], rs1, f[2:0], rd, 7'h03};
			expect_ctrl("load", {{21{imm[11]}}, imm[10:0]}, 1, 4'bxxxx, 0);

			f = {$random} % 3;
			ir = {imm[11:5], rs2, rs1, f[2:0], imm[4:0], 7'h23};
			rd = ir[11:7];
			expect_ctrl("store", {{21{imm[11]}}, imm[10:0]}, 0, 4'bxxxx, 0);

			// OP-IMM: bit 30 is immediate except for SRAI
			rd = $random;
			f = {$random} % 8;
			if (f == 1 || f == 5)
				imm[11:5] = f == 5 && imm[0] ? 7'b0100000 : 7'b0000000;
			ir = {imm[11:0], rs1, f[2:0], rd, 7'h13};
			expect_ctrl("opimm", {{21{imm[11]}}, imm[10:0]}, 1,
			            {f == 5 && imm[10], f[2:0]}, 1);

			// OP
			f = {$random} % 8;
			imm[11:5] = (f == 0 || f == 5) && imm[0] ? 7'b0100000 : 7'b0000000;
			ir = {imm[11:5], rs2, rs1, f[2:0], rd, 7'h33};
			expect_ctrl("op", {{21{ir[31]}}, ir[30:20]}, 1, {imm[10], f[2:0]}, 0);

			// counter read: csrrs rd, csr, x0 (and the other read forms)
			f = 2 + ({$random} % 2) + 4 * ({$random} % 2);
			ir = {imm[11:0], 5'd0, f[2:0], rd, 7'h73};
			expect_ctrl("csr", {{21{imm[11]}}, imm[10:0]}, 1, 4'bxxxx, 0);
		end

		if (errors == 0)
			$display("PASS: nt_decode (%0d checks, %0d legal encodings)", checks, legal_seen);
		else
			$display("FAIL: nt_decode: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
