// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_lsu: for every access size, signedness and byte offset, check the
// misalignment flag, the bus request (address, strobes, data in the
// strobed lanes) and the extracted load value.

`timescale 1 ns / 1 ps

module tb_lsu;

	reg         clk = 0;
	reg  [ 2:0] funct3;
	reg         is_store;
	reg  [31:0] addr, store_data, bus_rdata;
	reg         load_we = 0;
	wire        misaligned;
	wire [31:0] bus_addr, bus_wdata, load_data;
	wire [ 3:0] bus_wstrb;

	nt_lsu dut (
		.clk       (clk),
		.funct3    (funct3),
		.is_store  (is_store),
		.addr      (addr),
		.store_data(store_data),
		.misaligned(misaligned),
		.bus_addr  (bus_addr),
		.bus_wdata (bus_wdata),
		.bus_wstrb (bus_wstrb),
		.load_we   (load_we),
		.bus_rdata (bus_rdata),
		.load_data (load_data)
	);

	integer errors = 0, checks = 0;
	integer f, ofs, n, lane;
	integer bytes;
	reg [31:0] exp_load;
	reg [ 3:0] exp_strb;
	reg        exp_mis;

	task fail(input [8*40-1:0] what);
		begin
			errors = errors + 1;
			if (errors <= 10)
				$display("  funct3=%b store=%b addr=%08x: %0s", funct3, is_store, addr, what);
		end
	endtask

	initial begin
		for (n = 0; n < 200; n = n + 1)
			for (f = 0; f < 8; f = f + 1)
				for (ofs = 0; ofs < 4; ofs = ofs + 1) begin
					// LB LH LW LBU LHU and SB SH SW
					if (f == 3 || f >= 6)
						;
					else begin
						funct3     = f;
						is_store   = n % 2;
						if (is_store && f >= 3)
							is_store = 0;
						addr       = {$random} & 32'hffff_fffc | ofs;
						store_data = $random;
						bus_rdata  = $random;

						bytes    = 1 << f[1:0];
						exp_mis  = (addr % bytes) != 0;
						exp_strb = exp_mis ? 4'bxxxx : ((1 << bytes) - 1) << ofs;

						#1;
						checks = checks + 1;
						if (misaligned !== exp_mis)
							fail("misaligned");
						if (!exp_mis) begin
							if (bus_addr !== (addr & 32'hffff_fffc))
								fail("bus_addr");
							if (bus_wstrb !== (is_store ? exp_strb : 4'b0000))
								fail("bus_wstrb");
							for (lane = 0; lane < 4; lane = lane + 1)
								if (exp_strb[lane] && bus_wdata[lane*8 +: 8] !== store_data[(lane - ofs)*8 +: 8])
									fail("bus_wdata");

							if (!is_store) begin
								exp_load = bus_rdata >> (ofs * 8);
								case (f)
									0: exp_load = {{24{exp_load[7]}}, exp_load[7:0]};
									1: exp_load = {{16{exp_load[15]}}, exp_load[15:0]};
									4: exp_load = {24'b0, exp_load[7:0]};
									5: exp_load = {16'b0, exp_load[15:0]};
								endcase
								load_we = 1;
								#4 clk = 1;
								#5 clk = 0;
								load_we = 0;
								if (load_data !== exp_load)
									fail("load_data");
							end
						end
					end
				end

		if (errors == 0)
			$display("PASS: nt_lsu (%0d checks)", checks);
		else
			$display("FAIL: nt_lsu: %0d of %0d checks failed", errors, checks);
		$finish;
	end

endmodule
