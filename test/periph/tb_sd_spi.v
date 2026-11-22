// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// nt_sd_spi against a small SPI mode 0 slave that answers each byte with
// the previous one inverted: transfers at two clock dividers, SCK period,
// manual pin control, the busy flag and the register read-back.

`timescale 1 ns / 1 ps

module tb_sd_spi;

	reg clk = 0;
	always #20 clk = ~clk;
	reg resetn = 0;

	reg         valid = 0;
	reg  [31:0] addr, wdata;
	reg  [ 3:0] wstrb;
	wire        ready;
	wire [31:0] rdata;
	wire        sck, mosi, cs;
	reg         miso;

	nt_sd_spi #(.DEFAULT_DIV(8'd3)) dut (
		.clk(clk), .resetn(resetn),
		.valid(valid), .addr(addr), .wdata(wdata), .wstrb(wstrb),
		.ready(ready), .rdata(rdata),
		.sd_sck(sck), .sd_mosi(mosi), .sd_cs(cs), .sd_miso(miso)
	);

	// slave: samples MOSI on the rising edge, shifts out on the falling edge
	reg [7:0] s_in, s_out, s_next;
	integer   s_bits = 0;
	initial s_next = 8'h5A;
	always @(negedge cs) begin s_out = s_next; s_bits = 0; miso = s_out[7]; end
	always @(posedge sck) if (!cs) begin
		s_in   = {s_in[6:0], mosi};
		s_bits = s_bits + 1;
		if (s_bits == 8) begin s_bits = 0; s_next = ~s_in; end
	end
	always @(negedge sck) if (!cs) begin
		if (s_bits == 0) s_out = s_next; else s_out = {s_out[6:0], 1'b0};
		miso = s_out[7];
	end

	// SCK period
	realtime t_rise, period;
	always @(posedge sck) begin period = $realtime - t_rise; t_rise = $realtime; end

	integer errors = 0, i;
	reg [31:0] r;

	task access(input [31:0] a, input [3:0] s, input [31:0] d, output [31:0] q);
		begin
			@(posedge clk);
			valid <= 1; addr <= a; wstrb <= s; wdata <= d;
			@(posedge clk);
			while (!ready) @(posedge clk);
			q = rdata;
			valid <= 0;
		end
	endtask

	task xfer(input [7:0] tx, output [7:0] rx);
		begin
			access(32'h0, 4'b0001, tx, r);
			access(32'h8, 4'b0000, 0, r);
			if (!r[4]) begin errors = errors + 1; $display("  busy not set"); end
			while (r[4]) access(32'h8, 4'b0000, 0, r);
			access(32'h4, 4'b0000, 0, r);
			rx = r[7:0];
		end
	endtask

	task check_eq(input [31:0] got, input [31:0] want, input [8*24-1:0] what);
		if (got !== want) begin
			errors = errors + 1;
			$display("  %0s: got %0h, expected %0h", what, got, want);
		end
	endtask

	reg [7:0] rx, prev;

	initial begin
		miso = 1;
		repeat (3) @(posedge clk);
		resetn <= 1;

		access(32'h8, 4'b0000, 0, r);
		check_eq(r[2:0], 3'b110, "reset pins (CS high, MOSI high, SCK low)");
		access(32'hC, 4'b0000, 0, r);
		check_eq(r, 3, "reset divider");

		// manual pins
		access(32'h8, 4'b0001, 3'b101, r);    // CS high, MOSI low, SCK high
		#1 check_eq({cs, mosi, sck}, 3'b101, "manual pins");
		access(32'h8, 4'b0001, 3'b000, r);    // CS low, MOSI low, SCK low
		#1 check_eq({cs, mosi, sck}, 3'b000, "manual pins");

		prev = 8'h5A;
		for (i = 0; i < 40; i = i + 1) begin
			if (i == 20) begin
				access(32'hC, 4'b0001, 9, r);  // slower clock
				access(32'hC, 4'b0000, 0, r);
				check_eq(r, 9, "divider");
			end
			xfer(i * 29 + 3, rx);
			check_eq(rx, prev, "received byte");
			prev = ~(i * 29 + 3);
			check_eq(period, (i < 20 ? 3 : 9) * 2 * 40, "SCK period");
		end

		if (errors == 0)
			$display("PASS: nt_sd_spi");
		else
			$display("FAIL: nt_sd_spi: %0d errors", errors);
		$finish;
	end

endmodule
