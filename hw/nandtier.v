// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier SoC.
//
//   nandtier       top level for the Tang Nano 9K (GW1NR-9C): clocks from
//                  the Gowin rPLL and CLKDIV IP, and nandtier_soc
//   nandtier_soc   everything else, the same on every board; the board top
//                  levels in boards/ make its two clocks and instantiate it
//
// Memory map:
//   0x0000_0000  SPI flash, execute in place (16 MiB window), from flash
//                address FLASH_OFFSET on (0 on the Tang Nano 9K, whose
//                bitstream lives inside the FPGA; other boards keep the
//                bitstream at the start of the same flash)
//   0x4000_0000  SRAM, 8 KiB
//   0x8000_0000  boot RAM, 8 KiB (boot ROM image, reset vector)
//   0x8100_0000  SPI flash config / bit-bang register
//   0x8200_0000  GPIO
//   0x8300_0000  UART (every byte sent also goes to the HDMI terminal)
//   0xC000_0000  SD card SPI port
//   0xC100_0000  picture processing unit (tiles, sprites; see hw/video/nt_ppu.v)
//   0xC200_0000  on-chip logic analyzer (CPU bus trace)
//
// Clocks: clk_sys of about 25 MHz for the CPU, the bus and the 640x480
// pixel clock, and clk_5x for the HDMI serialisers. On the Tang Nano 9K:
// 27 MHz in -> rPLL 124.875 MHz (clk_5x) -> CLKDIV /5 -> 24.975 MHz.

`timescale 1 ns / 1 ps

module nandtier #(
	parameter [23:0] FLASH_OFFSET = 24'h000000
) (
	input        clk,           // 27 MHz crystal
	input        resetn,        // S1 button, active low

	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p,

	input        sd_miso,
	output       sd_cs,
	output       sd_mosi,
	output       sd_clk,

	output       flash_clk,
	output       flash_csb,
	inout        flash_mosi,
	inout        flash_miso,

	input        ser_rx,
	output       ser_tx,
	inout  [6:0] gpio
);
	wire clk_5x, clk_sys, pll_lock;

	Gowin_rPLL u_pll (
		.clkin (clk),
		.clkout(clk_5x),
		.lock  (pll_lock)
	);

	Gowin_CLKDIV u_clkdiv (
		.hclkin(clk_5x),
		.resetn(pll_lock),
		.clkout(clk_sys)
	);

	nandtier_soc #(
		.FLASH_OFFSET(FLASH_OFFSET)
	) u_soc (
		.clk_sys(clk_sys), .clk_5x(clk_5x), .pll_lock(pll_lock), .resetn(resetn),
		.tmds_clk_n(tmds_clk_n), .tmds_clk_p(tmds_clk_p), .tmds_d_n(tmds_d_n), .tmds_d_p(tmds_d_p),
		.sd_miso(sd_miso), .sd_cs(sd_cs), .sd_mosi(sd_mosi), .sd_clk(sd_clk),
		.flash_clk(flash_clk), .flash_csb(flash_csb), .flash_mosi(flash_mosi), .flash_miso(flash_miso),
		.ser_rx(ser_rx), .ser_tx(ser_tx), .gpio(gpio)
	);

endmodule

module nandtier_soc #(
	parameter [23:0] FLASH_OFFSET = 24'h000000,   // flash address of CPU address 0
	parameter  [6:0] GPIO_INVERT  = 7'd0,         // pins wired the other way round (LEDs)
	parameter        TRUE_LVDS    = 0,            // Gowin HDMI: TLVDS_OBUF, not ELVDS_OBUF
	parameter        ENABLE_ECP5_JTAG = 0
) (
	input        clk_sys,       // about 25 MHz: CPU, bus, pixel clock
	input        clk_5x,        // 5 x clk_sys, in phase: HDMI serialisers
	input        pll_lock,      // clocks are good
	input        resetn,        // reset button, active low

	output       tmds_clk_n,
	output       tmds_clk_p,
	output [2:0] tmds_d_n,
	output [2:0] tmds_d_p,

	input        sd_miso,
	output       sd_cs,
	output       sd_mosi,
	output       sd_clk,

	output       flash_clk,
	output       flash_csb,
	inout        flash_mosi,
	inout        flash_miso,

	input        ser_rx,
	output       ser_tx,
	inout  [6:0] gpio
);
	// --- reset -------------------------------------------------------------------

	wire sys_resetn;

	nt_reset_sync u_reset (
		.clk       (clk_sys),
		.ext_resetn(resetn && pll_lock),
		.resetn    (sys_resetn)
	);

	// --- CPU ---------------------------------------------------------------------

	wire        cpu_valid, cpu_ready, cpu_instr, cpu_trap;
	wire [31:0] cpu_addr, cpu_wdata, cpu_rdata;
	wire [ 3:0] cpu_wstrb;
	wire        cpu_debug_halted, cpu_debug_halt_request;
	wire        cpu_debug_resume, cpu_debug_step;
	wire        cpu_debug_pc_we, cpu_debug_reg_we, cpu_debug_reset;
	wire [31:0] cpu_debug_pc, cpu_debug_pc_wdata;
	wire [ 4:0] cpu_debug_reg_addr;
	wire [31:0] cpu_debug_reg_rdata, cpu_debug_reg_wdata;
	wire        cpu_dbg_valid, cpu_dbg_ready, cpu_dbg_error;
	wire [ 7:0] cpu_dbg_addr;
	wire [31:0] cpu_dbg_wdata, cpu_dbg_rdata;
	wire [ 3:0] cpu_dbg_wstrb;
	wire        soc_resetn = sys_resetn && !cpu_debug_reset;

	nandtier_core #(
		.PROGADDR_RESET(32'h8000_0000),
		.ENABLE_CPU_DEBUG(ENABLE_ECP5_JTAG)
	) u_cpu (
		.clk      (clk_sys),
		.resetn   (soc_resetn),
		.debug_halt_request(cpu_debug_halt_request),
		.debug_resume(cpu_debug_resume),
		.debug_step(cpu_debug_step),
		.debug_pc_we(cpu_debug_pc_we),
		.debug_pc_wdata(cpu_debug_pc_wdata),
		.debug_reg_addr(cpu_debug_reg_addr),
		.debug_reg_we(cpu_debug_reg_we),
		.debug_reg_wdata(cpu_debug_reg_wdata),
		.trap     (cpu_trap),
		.debug_halted(cpu_debug_halted),
		.debug_pc(cpu_debug_pc),
		.debug_reg_rdata(cpu_debug_reg_rdata),
		.mem_valid(cpu_valid),
		.mem_instr(cpu_instr),
		.mem_ready(cpu_ready),
		.mem_addr (cpu_addr),
		.mem_wdata(cpu_wdata),
		.mem_wstrb(cpu_wstrb),
		.mem_rdata(cpu_rdata)
	);

	// --- bus: top level (address bits 31:30) ----------------------------------------

	wire [3:0]  top_valid, top_ready;
	wire [31:0] flash_rdata, sram_rdata, periph_rdata, ext_rdata;

	nt_bus_mux4 #(
		.BASE0(32'h0000_0000), .MASK0(32'hC000_0000),
		.BASE1(32'h4000_0000), .MASK1(32'hC000_0000),
		.BASE2(32'h8000_0000), .MASK2(32'hC000_0000),
		.BASE3(32'hC000_0000), .MASK3(32'hC000_0000)
	) u_bus_top (
		.m_valid (cpu_valid),
		.m_addr  (cpu_addr),
		.m_ready (cpu_ready),
		.m_rdata (cpu_rdata),
		.s_valid (top_valid),
		.s_ready (top_ready),
		.s0_rdata(flash_rdata),
		.s1_rdata(sram_rdata),
		.s2_rdata(periph_rdata),
		.s3_rdata(ext_rdata)
	);

	// --- bus: peripherals at 0x8n00_0000 ----------------------------------------------

	wire [3:0]  per_valid, per_ready;
	wire [31:0] bootram_rdata, flashcfg_rdata, gpio_rdata, uart_rdata;

	nt_bus_mux4 #(
		.BASE0(32'h8000_0000), .MASK0(32'h0F00_0000),
		.BASE1(32'h8100_0000), .MASK1(32'h0F00_0000),
		.BASE2(32'h8200_0000), .MASK2(32'h0F00_0000),
		.BASE3(32'h8300_0000), .MASK3(32'h0F00_0000)
	) u_bus_periph (
		.m_valid (top_valid[2]),
		.m_addr  (cpu_addr),
		.m_ready (top_ready[2]),
		.m_rdata (periph_rdata),
		.s_valid (per_valid),
		.s_ready (per_ready),
		.s0_rdata(bootram_rdata),
		.s1_rdata(flashcfg_rdata),
		.s2_rdata(gpio_rdata),
		.s3_rdata(uart_rdata)
	);

	// --- memories ----------------------------------------------------------------

	nt_sram u_sram (
		.clk(clk_sys), .resetn(soc_resetn),
		.valid(top_valid[1]), .addr(cpu_addr), .wdata(cpu_wdata), .wstrb(cpu_wstrb),
		.ready(top_ready[1]), .rdata(sram_rdata)
	);

	nt_boot_ram u_boot_ram (
		.clk(clk_sys), .resetn(soc_resetn),
		.valid(per_valid[0]), .addr(cpu_addr), .wdata(cpu_wdata), .wstrb(cpu_wstrb),
		.ready(per_ready[0]), .rdata(bootram_rdata)
	);

	// --- SPI flash, behind a 4 KiB read cache ----------------------------------------

	wire        fl_valid, fl_ready, flash_restart;
	wire [23:0] fl_addr;
	wire [3:0]  fl_wstrb;
	wire [31:0] fl_rdata;
	wire        flash_io0_oe, flash_io0_do, flash_io1_oe, flash_io1_do;

	nt_flash_cache u_cache (
		.clk(clk_sys), .resetn(soc_resetn), .invalidate(flash_restart),
		.valid(top_valid[0]), .addr(cpu_addr[23:0]), .wstrb(cpu_wstrb),
		.ready(top_ready[0]), .rdata(flash_rdata),
		.f_valid(fl_valid), .f_addr(fl_addr), .f_wstrb(fl_wstrb),
		.f_ready(fl_ready), .f_rdata(fl_rdata)
	);

	nt_spi_flash u_flash (
		.clk(clk_sys), .resetn(soc_resetn),
		.mem_valid(fl_valid), .mem_addr(fl_addr + FLASH_OFFSET), .mem_wstrb(fl_wstrb),
		.mem_ready(fl_ready), .mem_rdata(fl_rdata),
		.cfg_valid(per_valid[1]), .cfg_wstrb(cpu_wstrb), .cfg_wdata(cpu_wdata),
		.cfg_ready(per_ready[1]), .cfg_rdata(flashcfg_rdata), .restart(flash_restart),
		.flash_csb(flash_csb), .flash_clk(flash_clk),
		.io0_oe(flash_io0_oe), .io0_do(flash_io0_do), .io0_di(flash_mosi),
		.io1_oe(flash_io1_oe), .io1_do(flash_io1_do), .io1_di(flash_miso)
	);

	assign flash_mosi = flash_io0_oe ? flash_io0_do : 1'bz;
	assign flash_miso = flash_io1_oe ? flash_io1_do : 1'bz;

	// --- GPIO and UART -------------------------------------------------------------

	nt_gpio #(
		.WIDTH (7),
		.INVERT(GPIO_INVERT)
	) u_gpio (
		.clk(clk_sys), .resetn(soc_resetn),
		.valid(per_valid[2]), .addr(cpu_addr), .wdata(cpu_wdata), .wstrb(cpu_wstrb),
		.ready(per_ready[2]), .rdata(gpio_rdata),
		.io(gpio)
	);

	nt_uart u_uart (
		.clk(clk_sys), .resetn(soc_resetn),
		.valid(per_valid[3]), .addr(cpu_addr), .wdata(cpu_wdata), .wstrb(cpu_wstrb),
		.ready(per_ready[3]), .rdata(uart_rdata),
		.rx(ser_rx), .tx(ser_tx)
	);

	// every byte written to the UART data register also goes to the screen
	wire term_valid = per_valid[3] && per_ready[3] && !cpu_addr[2] && cpu_wstrb[0];

	// --- 0xCxxx_xxxx: SD card, PPU and on-chip logic analyzer -------------------------

	wire [3:0]  ext_valid;
	wire        sdspi_ready, ppu_ready, ila_ready;
	wire [31:0] sdspi_rdata, ppu_rdata, ila_rdata;
	wire        ila_dbg_valid, ila_dbg_ready;
	wire [7:0]  ila_dbg_addr;
	wire [31:0] ila_dbg_wdata, ila_dbg_rdata;
	wire [3:0]  ila_dbg_wstrb;

	nt_bus_mux4 #(
		.BASE0(32'hC000_0000), .MASK0(32'hFF00_0000),
		.BASE1(32'hC100_0000), .MASK1(32'hFF00_0000),
		.BASE2(32'hC200_0000), .MASK2(32'hFF00_0000),
		.BASE3(32'h0000_0000), .MASK3(32'hFF00_0000)
	) u_bus_ext (
		.m_valid (top_valid[3]),
		.m_addr  (cpu_addr),
		.m_ready (top_ready[3]),
		.m_rdata (ext_rdata),
		.s_valid (ext_valid),
		.s_ready ({1'b0, ila_ready, ppu_ready, sdspi_ready}),
		.s0_rdata(sdspi_rdata),
		.s1_rdata(ppu_rdata),
		.s2_rdata(ila_rdata),
		.s3_rdata(32'd0)
	);

	nt_sd_spi u_sd_spi (
		.clk(clk_sys), .resetn(soc_resetn),
		.valid(ext_valid[0]), .addr(cpu_addr), .wdata(cpu_wdata), .wstrb(cpu_wstrb),
		.ready(sdspi_ready), .rdata(sdspi_rdata),
		.sd_sck(sd_clk), .sd_mosi(sd_mosi), .sd_cs(sd_cs), .sd_miso(sd_miso)
	);

	nt_ila u_ila (
		.clk(clk_sys), .resetn(soc_resetn),
		.valid(ext_valid[2]), .addr(cpu_addr), .wdata(cpu_wdata), .wstrb(cpu_wstrb),
		.ready(ila_ready), .rdata(ila_rdata),
		.dbg_valid(ila_dbg_valid), .dbg_addr(ila_dbg_addr),
		.dbg_wdata(ila_dbg_wdata), .dbg_wstrb(ila_dbg_wstrb),
		.dbg_ready(ila_dbg_ready), .dbg_rdata(ila_dbg_rdata),
		.bus_valid(cpu_valid), .bus_ready(cpu_ready), .bus_addr(cpu_addr),
		.bus_wdata(cpu_wdata), .bus_wstrb(cpu_wstrb), .bus_rdata(cpu_rdata),
		.bus_instr(cpu_instr), .bus_trap(cpu_trap)
	);

	generate
		if (ENABLE_ECP5_JTAG) begin : gen_ecp5_jtag
			nt_cpu_debug u_cpu_debug (
				.clk(clk_sys), .resetn(sys_resetn),
				.valid(cpu_dbg_valid), .addr(cpu_dbg_addr),
				.wdata(cpu_dbg_wdata), .wstrb(cpu_dbg_wstrb),
				.ready(cpu_dbg_ready), .rdata(cpu_dbg_rdata),
				.error(cpu_dbg_error),
				.core_halted(cpu_debug_halted), .core_trap(cpu_trap),
				.core_pc(cpu_debug_pc),
				.core_reg_rdata(cpu_debug_reg_rdata),
				.core_halt_request(cpu_debug_halt_request),
				.core_resume(cpu_debug_resume),
				.core_step(cpu_debug_step),
				.core_pc_we(cpu_debug_pc_we),
				.core_pc_wdata(cpu_debug_pc_wdata),
				.core_reg_addr(cpu_debug_reg_addr),
				.core_reg_we(cpu_debug_reg_we),
				.core_reg_wdata(cpu_debug_reg_wdata),
				.system_reset(cpu_debug_reset)
			);

			nt_ecp5_jtag_ila u_jtag_ila (
				.clk_sys(clk_sys), .resetn_sys(sys_resetn),
				.ila_valid(ila_dbg_valid), .ila_addr(ila_dbg_addr),
				.ila_wdata(ila_dbg_wdata), .ila_wstrb(ila_dbg_wstrb),
				.ila_ready(ila_dbg_ready), .ila_rdata(ila_dbg_rdata),
				.cpu_valid(cpu_dbg_valid), .cpu_addr(cpu_dbg_addr),
				.cpu_wdata(cpu_dbg_wdata), .cpu_wstrb(cpu_dbg_wstrb),
				.cpu_ready(cpu_dbg_ready), .cpu_rdata(cpu_dbg_rdata),
				.cpu_error(cpu_dbg_error)
			);
		end else begin : gen_no_jtag
			assign ila_dbg_valid = 1'b0;
			assign ila_dbg_addr = 8'd0;
			assign ila_dbg_wdata = 32'd0;
			assign ila_dbg_wstrb = 4'd0;
			assign cpu_dbg_valid = 1'b0;
			assign cpu_dbg_addr = 8'd0;
			assign cpu_dbg_wdata = 32'd0;
			assign cpu_dbg_wstrb = 4'd0;
			assign cpu_debug_halt_request = 1'b0;
			assign cpu_debug_resume = 1'b0;
			assign cpu_debug_step = 1'b0;
			assign cpu_debug_pc_we = 1'b0;
			assign cpu_debug_pc_wdata = 32'd0;
			assign cpu_debug_reg_addr = 5'd0;
			assign cpu_debug_reg_we = 1'b0;
			assign cpu_debug_reg_wdata = 32'd0;
			assign cpu_debug_reset = 1'b0;
		end
	endgenerate

	// --- HDMI ------------------------------------------------------------------------

	nt_video #(
		.TRUE_LVDS(TRUE_LVDS)
	) u_video (
		.clk(clk_sys), .clk_5x(clk_5x), .resetn(soc_resetn),
		.term_valid(term_valid), .term_char(cpu_wdata[7:0]), .term_ready(),
		.ppu_valid(ext_valid[1]), .ppu_addr(cpu_addr[15:0]),
		.ppu_wdata(cpu_wdata), .ppu_wstrb(cpu_wstrb),
		.ppu_ready(ppu_ready), .ppu_rdata(ppu_rdata),
		.tmds_clk_p(tmds_clk_p), .tmds_clk_n(tmds_clk_n),
		.tmds_d_p(tmds_d_p), .tmds_d_n(tmds_d_n)
	);

endmodule
