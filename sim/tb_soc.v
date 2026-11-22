// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Whole-SoC simulation: hw/nandtier.v with the boot ROM in the boot RAM,
// the user firmware in sim/spi_flash_model.v and a UART on ser_rx/ser_tx.
//
// Plusargs:
//   +brom=<prefix>   boot RAM lanes <prefix>_0..3.hex (fw/fw-brom/build/fw-brom)
//   +isp             test the boot ROM's ISP commands instead of the firmware
//   +carts           the game menu: the launcher reads the cartridge pack
//                    from sim/sd_card_model.v (build/carts.hex), copies Pong
//                    into the flash cartridge slot and starts it; capture
//                    build/carts_menu.ppm and build/carts_pong.ppm, quit,
//                    start it again (no copy this time), quit
//   +trace           print every UART byte as it arrives
//   -P tb_soc.FLASH_OFFSET=<n> (iverilog): the firmware sits at flash
//                    address n, as on boards with the bitstream in the flash
//
// Default test: boot into the firmware, wait for the menu, read the flash
// ID (boot ROM flash_io() at 0x8000_0054), switch flash modes, run the
// benchmark, and check the HDMI terminal received the text.
// To keep this fast, rdcycle runs 1000x fast until the menu appears (the
// boot ROM's ISP window and the firmware's LED delay are cycle-timed), and
// the UART runs at 3.1 Mbaud.

`timescale 1 ns / 1 ps

module tb_soc #(
	// flash address of CPU address 0, as on boards whose bitstream is in the
	// flash: the firmware image is moved there before the CPU starts
	parameter [23:0] FLASH_OFFSET = 24'h000000
);

	// The UART runs at 8 clocks per bit here instead of 217 (115200 baud):
	// the firmware's menu alone would take a million clock cycles otherwise.
	localparam      UART_DIV = 8;
	localparam real BIT_NS   = UART_DIV * 1000.0 / 24.975;
	initial force dut.u_soc.u_uart.div = UART_DIV;

	reg  clk = 0;
	reg  resetn = 0;
	always #(1000.0 / 27 / 2) clk = !clk;

	wire       flash_clk, flash_csb, flash_mosi, flash_miso;
	wire       ser_tx;
	reg        ser_rx = 1;
	wire [6:0] gpio;
	wire       sd_cs, sd_mosi, sd_clk, sd_miso;
	wire [2:0] tmds_d_p, tmds_d_n;
	wire       tmds_clk_p, tmds_clk_n;

	GSR GSR (.GSRI(1'b1));      // Gowin simulation library global reset

	nandtier #(
		.FLASH_OFFSET(FLASH_OFFSET)
	) dut (
		.clk(clk), .resetn(resetn),
		.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
		.sd_miso(sd_miso), .sd_cs(sd_cs), .sd_mosi(sd_mosi), .sd_clk(sd_clk),
		.flash_clk(flash_clk), .flash_csb(flash_csb), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
		.ser_rx(ser_rx), .ser_tx(ser_tx), .gpio(gpio)
	);

	pullup (flash_mosi);
	pullup (flash_miso);

	spi_flash_model #(
		.SIZE     (8 * 1024 * 1024),
		.INIT_FILE("../fw/fw-flash/build/fw-flash.v")
	) flash (
		.csb(flash_csb), .sck(flash_clk), .io0(flash_mosi), .io1(flash_miso)
	);

	integer m;
	initial if (FLASH_OFFSET != 0) begin
		#1;
		for (m = 0; m < 'h40000; m = m + 1) begin
			flash.mem[FLASH_OFFSET + m] = flash.mem[m];
			flash.mem[m] = 8'hFF;
		end
		$display("tb_soc: firmware moved to flash offset 0x%06x", FLASH_OFFSET);
	end

	// the game cartridge pack (fw/games/build/carts.img, as bytes) on the card
	sd_card_model #(
		.BASE     (8192),
		.BLOCKS   (512),
		.INIT_FILE("build/carts.hex")
	) sd (
		.cs(sd_cs), .sck(sd_clk), .mosi(sd_mosi), .miso(sd_miso)
	);

	// --- boot RAM contents -------------------------------------------------------

	reg [1023:0] brom;
	reg [7:0]    lane0 [0:2047], lane1 [0:2047], lane2 [0:2047], lane3 [0:2047];
	integer      i;

	initial begin
		if (!$value$plusargs("brom=%s", brom))
			brom = "../fw/fw-brom/build/fw-brom";
		$readmemh({brom, "_0.hex"}, lane0);
		$readmemh({brom, "_1.hex"}, lane1);
		$readmemh({brom, "_2.hex"}, lane2);
		$readmemh({brom, "_3.hex"}, lane3);
		#1;
		for (i = 0; i < 2048; i = i + 1) begin
			dut.u_soc.u_boot_ram.u_lane0.sp_inst_0.ram_MEM[i * 8 +: 8] = lane0[i];
			dut.u_soc.u_boot_ram.u_lane1.sp_inst_0.ram_MEM[i * 8 +: 8] = lane1[i];
			dut.u_soc.u_boot_ram.u_lane2.sp_inst_0.ram_MEM[i * 8 +: 8] = lane2[i];
			dut.u_soc.u_boot_ram.u_lane3.sp_inst_0.ram_MEM[i * 8 +: 8] = lane3[i];
		end
	end

	// --- fast cycle counter --------------------------------------------------------

	reg fast = 1;
	always @(posedge dut.u_soc.clk_sys) if (fast && dut.u_soc.sys_resetn)
		#1 dut.u_soc.u_cpu.u_csr.cycle = dut.u_soc.u_cpu.u_csr.cycle + 999;

	// --- UART ------------------------------------------------------------------------

	reg [8*4096-1:0] rx_text = 0;       // everything received, newest char in bits 7:0
	integer          rx_count = 0;
	reg              trace;

	always begin : uart_receive
		reg [7:0] b;
		integer   k;
		@(negedge ser_tx);
		#(BIT_NS * 1.5);
		for (k = 0; k < 8; k = k + 1) begin
			b[k] = ser_tx;
			#(BIT_NS);
		end
		if (!ser_tx) $display("tb_soc: UART framing error");
		rx_text  = {rx_text[8*4095-1:0], b};
		rx_count = rx_count + 1;
		if (trace) begin
			if (b == 8'h0A || (b >= 8'h20 && b < 8'h7F)) $write("%c", b);
			else if (b != 8'h0D) $write("<%02x>", b);
			$fflush;
		end
	end

	task uart_send(input [7:0] b);
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

	// wait until the received text ends with `s` (up to 64 chars)
	task wait_for(input [8*64-1:0] s, input integer timeout_us);
		integer len, t;
		reg [8*64-1:0] mask;
		begin
			len = 0;
			while (len < 64 && s[len*8 +: 8] != 0) len = len + 1;
			mask = len == 64 ? {64{8'hFF}} : ({8*64{1'b1}} >> (8 * (64 - len)));
			t = 0;
			while ((rx_text[8*64-1:0] & mask) != (s & mask)) begin
				#1000;
				t = t + 1;
				if (t > timeout_us) begin
					$display("FAIL: tb_soc: timeout waiting for \"%0s\"", s);
					$finish;
				end
			end
		end
	endtask

	// true if `s` occurred anywhere in the received text
	function received(input [8*64-1:0] s);
		integer len, p;
		reg [8*64-1:0] mask;
		begin
			len = 0;
			while (len < 64 && s[len*8 +: 8] != 0) len = len + 1;
			mask = {8*64{1'b1}} >> (8 * (64 - len));
			received = 0;
			for (p = 0; p + len <= 4096; p = p + 1)
				if (((rx_text >> (8 * p)) & mask) == (s & mask))
					received = 1;
		end
	endfunction

	// --- HDMI terminal: is `s` somewhere on the screen? ------------------------------

	function on_screen(input [8*32-1:0] s);
		integer len, a, k;
		reg     match;
		begin
			len = 0;
			while (len < 32 && s[len*8 +: 8] != 0) len = len + 1;
			on_screen = 0;
			for (a = 0; a + len <= 2000; a = a + 1) begin
				match = 1;
				for (k = 0; k < len; k = k + 1)
					if (dut.u_soc.u_video.u_term.screen[a + k] != s[(len - 1 - k) * 8 +: 8])
						match = 0;
				if (match) on_screen = 1;
			end
		end
	endfunction

	// press a key in the firmware menu and wait for the next prompt
	task menu_key(input [7:0] key, input integer timeout_us);
		integer start;
		begin
			start = rx_count;
			uart_send(key);
			while (rx_count < start + 3)
				#1000;
			wait_for("> ", timeout_us);
		end
	endtask

	// --- PPU frame capture ----------------------------------------------------------
	//
	// The PPU colour of pixel (x, y) comes out 3 cycles after x, y; one
	// sample per picture pixel (even x and y). Written as a plain PPM.

	reg  [9:0]  cap_x [0:2];
	reg  [9:0]  cap_y [0:2];
	reg  [11:0] cap_img [0:256 * 240 - 1];
	reg         capturing = 0;

	always @(posedge dut.u_soc.clk_sys) begin
		cap_x[0] <= dut.u_soc.u_video.x; cap_x[1] <= cap_x[0]; cap_x[2] <= cap_x[1];
		cap_y[0] <= dut.u_soc.u_video.y; cap_y[1] <= cap_y[0]; cap_y[2] <= cap_y[1];
		if (capturing && dut.u_soc.u_video.ppu_active && !cap_x[2][0] && !cap_y[2][0])
			cap_img[(cap_y[2] >> 1) * 256 + ((cap_x[2] - 64) >> 1)] <= dut.u_soc.u_video.ppu_rgb;
	end

	task capture_frame(input [8*40-1:0] file);
		integer fd, k;
		reg [15:0] f;
		begin
			f = dut.u_soc.u_video.u_ppu.frame;
			while (dut.u_soc.u_video.u_ppu.frame == f) #1000;     // a vertical blank starts
			capturing = 1;
			f = dut.u_soc.u_video.u_ppu.frame;
			while (dut.u_soc.u_video.u_ppu.frame == f) #1000;     // one whole frame
			capturing = 0;
			fd = $fopen(file, "w");
			$fwrite(fd, "P3\n256 240\n15\n");
			for (k = 0; k < 256 * 240; k = k + 1)
				$fwrite(fd, "%0d %0d %0d\n", cap_img[k][11:8], cap_img[k][7:4], cap_img[k][3:0]);
			$fclose(fd);
			$display("tb_soc: captured %0s", file);
		end
	endtask

	task wait_frames(input integer n);
		reg [15:0] f;
		begin
			f = dut.u_soc.u_video.u_ppu.frame;
			while (dut.u_soc.u_video.u_ppu.frame - f < n) #1000;
		end
	endtask

	// --- tests -------------------------------------------------------------------------

	integer errors = 0;

	task check(input ok, input [8*48-1:0] what);
		if (!ok) begin
			errors = errors + 1;
			$display("tb_soc: FAILED: %0s", what);
		end else
			$display("tb_soc: ok: %0s", what);
	endtask

	task firmware_test;
		begin
			wait_for("> ", 60000);
			fast = 0;
			check(received("NandTier - select an action:"), "firmware menu on the UART");

			menu_key("I", 20000);
			check(received("Flash JEDEC ID: 85 60 16"), "flash ID through the boot ROM");
			check(FLASH_OFFSET == 24'h000000 ? received("Firmware at flash address 0x000000") :
			      FLASH_OFFSET == 24'h200000 ? received("Firmware at flash address 0x200000") : 0,
			      "launcher finds its flash offset");

			menu_key("S", 20000);
			check(received("Flash reads: single"), "switch to single flash reads");
			menu_key("C", 20000);
			check(received("Flash reads: dual I/O, continuous read mode"), "switch to dual + CRM");

			menu_key("B", 400000);
			check(received(" (ok)"), "benchmark result");

			check(on_screen("select an action"), "text on the HDMI terminal");
			check(flash.errors == 0, "no flash protocol errors");
		end
	endtask

	// The game menu: read the SD card, copy Pong (game 5) into the flash
	// cartridge slot, run it, quit back to the menu, start it again (now
	// without copying), quit, leave the menu.
	task carts_test;
		begin
			wait_for("> ", 60000);
			fast = 0;
			uart_send("P");
			wait_for(". Q goes back to the menu.", 200000);
			check(received("[5] PONG"), "game menu lists the games on the SD card");
			check(dut.u_soc.u_video.u_ppu.ctrl == 3'b011, "game menu on the PPU screen");
			capture_frame("build/carts_menu.ppm");

			uart_send("5");
			wait_for("Q quits.", 2000000);
			check(received(" copied to the flash."), "Pong copied from the SD card into the flash");
			check(sd.reads > 20 && sd.errors == 0, "SD card reads");
			wait_frames(3);
			check(dut.u_soc.u_video.u_ppu.ctrl == 3'b011, "Pong runs from the cartridge slot");
			capture_frame("build/carts_pong.ppm");   // compared with the PC build by the Makefile

			uart_send("q");
			while (!received(" of 419580 cycles")) #1000;
			wait_for(". Q goes back to the menu.", 200000);
			check(received("Slowest frame: ") && !received("Slowest frame: 0 "), "Pong reports its frame time");
			check(1, "back in the game menu after the game");

			uart_send("5");
			wait_for("Q quits.", 2000000);
			check(received("- in the flash already."), "second start: no copy, the CRC matches");
			wait_frames(2);
			uart_send("q");
			wait_for(". Q goes back to the menu.", 200000);
			uart_send("q");
			wait_for("> ", 200000);
			check(dut.u_soc.u_video.u_ppu.ctrl == 3'b100, "terminal back on after the game menu");
			check(flash.errors == 0, "no flash protocol errors");
		end
	endtask

	task isp_test;
		integer k;
		reg [7:0] sum;
		begin
			// ping until the boot ROM answers (it listens right after reset)
			while (!received({8'h56})) begin
				uart_send(8'h55);
				#2000;
			end
			check(1, "boot ROM answers the ISP ping");

			// page buffer: 16 bytes, then erase sector 0x7F0000 and program
			uart_send(8'h10);
			wait_for({8'h11}, 20000);
			uart_send(8'd15);
			sum = 0;
			for (k = 0; k < 16; k = k + 1) begin
				uart_send(8'hC0 + k);
				sum = sum + 8'hC0 + k;
			end
			wait_for(sum, 20000);
			uart_send(8'h30); uart_send(8'h7F); uart_send(8'h00); uart_send(8'h00);
			wait_for({8'h31, 8'h32}, 50000);
			uart_send(8'h40); uart_send(8'h7F); uart_send(8'h00); uart_send(8'h10);
			wait_for({8'h41, 8'h42}, 50000);
			sum = 0;
			for (k = 0; k < 4096; k = k + 1)
				if (flash.mem[24'h7F0000 + k] !== (k >= 16 && k < 32 ? 8'hC0 + k - 16 : 8'hFF))
					sum = 1;
			check(sum == 0, "ISP erase and page program");
			check(flash.errors == 0, "no flash protocol errors");

			uart_send(8'hF0);
			wait_for({8'hF1}, 20000);
			check(1, "ISP restart");
		end
	endtask

	initial begin
		trace = $test$plusargs("trace");
		#200;
		resetn = 1;
		if ($test$plusargs("isp")) begin
			fast = 0;
			isp_test;
		end else if ($test$plusargs("carts"))
			carts_test;
		else
			firmware_test;

		if (errors == 0)
			$display("PASS: tb_soc (%0s)", $test$plusargs("isp") ? "boot ROM ISP" :
			         $test$plusargs("carts") ? "game cartridges" :
			         "firmware");
		else
			$display("FAIL: tb_soc: %0d checks failed", errors);
		$finish;
	end

endmodule
