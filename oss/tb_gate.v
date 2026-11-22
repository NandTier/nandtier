// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Gate-level check of the open-source flow's netlist (build/<board>/gate.v,
// from Yosys) with the Gowin primitive simulation models (prim_sim.v from a
// Gowin IDE install): an independent check of how Yosys mapped the design.
// For the Tang Nano 9K, or with TB_TANGNANO20K for the Tang Nano 20K.
//
// A full firmware boot would take hours at gate level, so this tests what
// the boot ROM does in its first milliseconds, at the real 115200 baud:
//   - the CPU runs the boot ROM from the block RAMs (their init values)
//     and answers the programmer's ping (0x55 -> 0x56)
//   - ISP: fill the page buffer, erase a flash sector, program a page, over
//     the MSPI pins into sim/spi_flash_model.v
//   - HDMI: the TMDS clock pair (rPLL -> CLKDIV -> OSER10 -> ELVDS_OBUF)
//     runs at the pixel clock, 24.975 MHz

`timescale 1 ns / 1 ps

module tb_gate;

	localparam real BIT_NS = 1.0e9 / 115200;

	reg  clk = 0;
	reg  resetn = 0;
	always #(1000.0 / 27 / 2) clk = !clk;

	wire       flash_clk, flash_csb, flash_mosi, flash_miso;
	wire       ser_tx;
	reg        ser_rx = 1;
	wire [6:0] gpio;
	wire       sd_cs, sd_mosi, sd_clk;
	wire [2:0] tmds_d_p, tmds_d_n;
	wire       tmds_clk_p, tmds_clk_n;

	GSR GSR (.GSRI(1'b1));

`ifdef TB_TANGNANO20K
	wire [5:0] led;
	assign gpio = 7'bz;

	nt_tangnano20k dut (
		.clk(clk), .btn_s1(!resetn),
		.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
		.sd_miso(1'b1), .sd_cs(sd_cs), .sd_mosi(sd_mosi), .sd_clk(sd_clk),
		.flash_clk(flash_clk), .flash_csb(flash_csb), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
		.ser_rx(ser_rx), .ser_tx(ser_tx), .led(led)
	);
`else
	nandtier dut (
		.clk(clk), .resetn(resetn),
		.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
		.sd_miso(1'b1), .sd_cs(sd_cs), .sd_mosi(sd_mosi), .sd_clk(sd_clk),
		.flash_clk(flash_clk), .flash_csb(flash_csb), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
		.ser_rx(ser_rx), .ser_tx(ser_tx), .gpio(gpio)
	);
`endif

	pullup (flash_mosi);
	pullup (flash_miso);

	spi_flash_model #(.SIZE(8 * 1024 * 1024)) flash (
		.csb(flash_csb), .sck(flash_clk), .io0(flash_mosi), .io1(flash_miso)
	);

	// --- UART --------------------------------------------------------------------------

	reg [7:0] rx_bytes [0:63];
	integer   rx_count = 0;

	always begin : receive
		reg [7:0] b;
		integer   k;
		@(negedge ser_tx);
		#(BIT_NS * 1.5);
		for (k = 0; k < 8; k = k + 1) begin
			b[k] = ser_tx;
			#(BIT_NS);
		end
		rx_bytes[rx_count % 64] = b;
		rx_count = rx_count + 1;
		$display("tb_gate: %0.1f us: received %02x", $realtime / 1000.0, b);
	end

	task send(input [7:0] b);
		integer k;
		begin
			ser_rx = 0;
			#(BIT_NS);
			for (k = 0; k < 8; k = k + 1) begin
				ser_rx = b[k];
				#(BIT_NS);
			end
			ser_rx = 1;
			#(BIT_NS);
		end
	endtask

	// wait until `n` bytes have arrived since rx_count was `start`; the last
	// one must be `want`
	task expect_bytes(input integer start, input integer n, input [7:0] want, input [8*40-1:0] what);
		integer t;
		begin
			for (t = 0; t < 400 && rx_count < start + n; t = t + 1)
				#(BIT_NS);
			check(rx_count >= start + n && rx_bytes[(start + n - 1) % 64] == want, what);
		end
	endtask

	integer errors = 0;

	task check(input ok, input [8*40-1:0] what);
		if (ok) $display("tb_gate: ok: %0s", what);
		else begin
			errors = errors + 1;
			$display("tb_gate: FAILED: %0s", what);
		end
	endtask

	// --- HDMI clock pair -----------------------------------------------------------------

	integer edges = 0;
	reg     counting = 0;
	always @(posedge tmds_clk_p) if (counting) edges = edges + 1;

	// --- test ------------------------------------------------------------------------------

	integer k, ok, mark;
	reg [7:0] sum;

	initial begin
		#1000;
		resetn = 1;
		#20000;                             // PLL lock, reset release, boot ROM start

		counting = 1;
		#10000;                             // 10 us
		counting = 0;
		$display("tb_gate: TMDS clock: %0d rising edges in 10 us", edges);
		check(edges >= 245 && edges <= 254, "HDMI clock pair at 24.975 MHz");
		check(tmds_clk_n === !tmds_clk_p, "HDMI clock pair is differential");

		mark = rx_count;
		send(8'h55);
		expect_bytes(mark, 1, 8'h56, "boot ROM answers the ping");

		// page buffer: 4 bytes, erase sector 0x200000, program them at 0x200010
		mark = rx_count;
		send(8'h10);
		send(8'd3);
		sum = 0;
		for (k = 0; k < 4; k = k + 1) begin
			send(8'hA0 + k);
			sum = sum + 8'hA0 + k;
		end
		expect_bytes(mark, 1, 8'h11, "ISP: page buffer command");
		expect_bytes(mark, 2, sum, "ISP: page buffer checksum");
		mark = rx_count;
		send(8'h30); send(8'h20); send(8'h00); send(8'h00);
		expect_bytes(mark, 2, 8'h32, "ISP: sector erase");
		mark = rx_count;
		send(8'h40); send(8'h20); send(8'h00); send(8'h10);
		expect_bytes(mark, 2, 8'h42, "ISP: page program");
		ok = 1;
		for (k = 0; k < 4; k = k + 1)
			if (flash.mem[24'h200010 + k] !== 8'hA0 + k) ok = 0;
		check(ok && flash.mem[24'h200014] === 8'hFF, "flash holds the programmed bytes");
		check(flash.errors == 0, "no flash protocol errors");

		if (errors == 0) $display("PASS: tb_gate (open-source netlist, Gowin models)");
		else $display("FAIL: tb_gate: %0d checks failed", errors);
		$finish;
	end

	initial begin
		#40_000_000;
		$display("FAIL: tb_gate: timeout");
		$finish;
	end

endmodule
