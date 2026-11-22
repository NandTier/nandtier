// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_bus_mux4 address decoding, with the two configurations used in
// hw/nandtier.v:
//   top:    0x0.. flash, 0x4.. SRAM, 0x8.. peripherals, 0xC.. SD
//   periph: 0x80.. boot RAM, 0x81.. flash config, 0x82.. GPIO, 0x83.. UART
// plus ready/rdata routing and the immediate answer for unmapped addresses.

`timescale 1 ns / 1 ps

module tb_bus_mux4;

	reg         m_valid;
	reg  [31:0] m_addr;
	reg  [ 3:0] s_ready;
	wire [3:0]  top_valid, per_valid;
	wire        top_ready, per_ready;
	wire [31:0] top_rdata, per_rdata;

	nt_bus_mux4 u_top (
		.m_valid(m_valid), .m_addr(m_addr), .m_ready(top_ready), .m_rdata(top_rdata),
		.s_valid(top_valid), .s_ready(s_ready),
		.s0_rdata(32'h5000), .s1_rdata(32'h5001), .s2_rdata(32'h5002), .s3_rdata(32'h5003)
	);

	nt_bus_mux4 #(
		.BASE0(32'h8000_0000), .MASK0(32'h0F00_0000),
		.BASE1(32'h8100_0000), .MASK1(32'h0F00_0000),
		.BASE2(32'h8200_0000), .MASK2(32'h0F00_0000),
		.BASE3(32'h8300_0000), .MASK3(32'h0F00_0000)
	) u_per (
		.m_valid(m_valid), .m_addr(m_addr), .m_ready(per_ready), .m_rdata(per_rdata),
		.s_valid(per_valid), .s_ready(s_ready),
		.s0_rdata(32'h5000), .s1_rdata(32'h5001), .s2_rdata(32'h5002), .s3_rdata(32'h5003)
	);

	integer errors = 0, checks = 0;

	// slave: 0..3, or -1 for unmapped
	task check_one(input [8*6-1:0] name, input integer slave,
	               input [3:0] valid_v, input ready, input [31:0] rdata);
		begin
			checks = checks + 1;
			if (slave < 0) begin
				if (valid_v !== 4'b0000 || ready !== 1'b1 || rdata !== 32'd0) begin
					errors = errors + 1;
					$display("  %0s %08x: expected unmapped, valid=%b ready=%b rdata=%h",
					         name, m_addr, valid_v, ready, rdata);
				end
			end else if (valid_v !== (4'b0001 << slave) || rdata !== 32'h5000 + slave) begin
				errors = errors + 1;
				$display("  %0s %08x: expected slave %0d, valid=%b rdata=%h", name, m_addr, slave, valid_v, rdata);
			end
		end
	endtask

	task check(input [31:0] addr, input integer top_slave, input integer per_slave);
		begin
			m_addr  = addr;
			m_valid = 1;
			s_ready = 4'b1111;
			#1;
			check_one("top", top_slave, top_valid, top_ready, top_rdata);
			if (per_slave != -2)
				check_one("periph", per_slave, per_valid, per_ready, per_rdata);
			// ready follows the selected slave only
			if (top_slave >= 0) begin
				s_ready = ~(4'b0001 << top_slave);
				#1 if (top_ready !== 1'b0) begin
					errors = errors + 1;
					$display("  top %08x: ready from a slave that is not selected", addr);
				end
			end
			m_valid = 0;
			#1 if (top_valid !== 4'b0000) begin
				errors = errors + 1;
				$display("  top %08x: valid without m_valid", addr);
			end
		end
	endtask

	initial begin
		check(32'h0000_0000, 0, -2);
		check(32'h007F_FFFC, 0, -2);
		check(32'h3FFF_FFFC, 0, -2);
		check(32'h4000_0000, 1, -2);
		check(32'h4000_1FFC, 1, -2);
		check(32'h8000_0000, 2, 0);
		check(32'h8000_1FFC, 2, 0);
		check(32'h8100_0000, 2, 1);
		check(32'h8200_0008, 2, 2);
		check(32'h8300_0004, 2, 3);
		check(32'h8400_0000, 2, -1);
		check(32'h8F00_0000, 2, -1);
		check(32'hC000_0008, 3, -2);
		check(32'hC001_001C, 3, -2);

		if (errors == 0)
			$display("PASS: nt_bus_mux4 (%0d checks)", checks);
		else
			$display("FAIL: nt_bus_mux4: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
