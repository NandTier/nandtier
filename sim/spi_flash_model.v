// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// Behavioural SPI NOR flash for simulation (SPI mode 0, IO0/IO1 only).
//
// Commands: 03h read, BBh dual I/O read (mode bits M5:4 = 10b keep the
// flash in continuous read mode: the next access starts with the address),
// 9Fh JEDEC ID, 05h status, 06h/04h write enable/disable, 20h 4 KiB
// sector erase, 02h page program, B9h deep power-down, ABh release from
// deep power-down, FFh ignored. Other commands are ignored.
//
// Checks (each prints "FLASH ERROR" and increments `errors`):
//   - a command within TRES1_NS of ABh, or while powered down
//   - erase/program without write enable, or while busy
//   - the controller driving a pin while the flash drives it
//
// The memory is loaded from INIT_FILE ($readmemh format, byte per entry).

`timescale 1 ns / 1 ps

module spi_flash_model #(
	parameter        SIZE      = 4 * 1024 * 1024,
	parameter        INIT_FILE = "",
	parameter [23:0] JEDEC_ID  = 24'h85_60_16,
	parameter        TRES1_NS  = 8000,
	parameter        BUSY_NS   = 2000,
	parameter        VERBOSE   = 0
) (
	input csb,
	input sck,
	inout io0,
	inout io1
);
	reg [7:0] mem [0:SIZE-1];
	integer   errors = 0;
	integer   i;

	initial begin
		for (i = 0; i < SIZE; i = i + 1)
			mem[i] = 8'hFF;
		if (INIT_FILE != "")
			$readmemh(INIT_FILE, mem);
	end

	// --- state --------------------------------------------------------------

	localparam [3:0] P_CMD = 0, P_ADDR = 1, P_MODE = 2, P_READ = 3, P_ID = 4,
	                 P_STATUS = 5, P_PROGRAM = 6, P_IGNORE = 7;

	reg  [3:0] phase;
	reg  [7:0] cmd;
	reg  [7:0] shift_in;
	integer    bits_in;         // bits of the current input byte
	integer    addr_bits;
	reg [23:0] addr;
	reg  [7:0] mode_bits;
	reg  [7:0] shift_out;
	integer    bits_out;
	reg        out_dual, out_en;
	reg        dual_in;
	reg        crm;             // continuous read mode active
	reg        wel, powered_down;
	realtime   wake_time, busy_until;
	integer    id_index;
	reg  [7:0] page [0:255];
	reg        page_used [0:255];
	reg [23:0] page_addr;
	reg        do_erase, do_program;   // the operation runs when CS goes high

	initial begin
		crm          = 0;
		wel          = 0;
		powered_down = 0;
		wake_time    = 0;
		busy_until   = 0;
		out_en       = 0;
	end

	assign io1 = out_en ? shift_out[7] : 1'bz;
	assign io0 = out_en && out_dual ? shift_out[6] : 1'bz;

	task error(input [8*60-1:0] msg);
		begin
			errors = errors + 1;
			$display("FLASH ERROR at %0t: %0s (cmd %02x)", $time, msg, cmd);
		end
	endtask

	function busy(input dummy);
		busy = $realtime < busy_until;
	endfunction

	// --- chip select ----------------------------------------------------------

	always @(negedge csb) begin
		bits_in    = 0;
		out_en     = 0;
		shift_in   = 0;
		do_erase   = 0;
		do_program = 0;
		if (crm) begin
			cmd       = 8'hBB;
			phase     = P_ADDR;
			dual_in   = 1;
			addr_bits = 0;
		end else begin
			phase   = P_CMD;
			dual_in = 0;
		end
	end

	always @(posedge csb) begin
		out_en = 0;
		if (do_program) begin
			for (i = 0; i < 256; i = i + 1)
				if (page_used[i])
					mem[{page_addr[23:8], 8'h00} + i] = mem[{page_addr[23:8], 8'h00} + i] & page[i];
			wel = 0;
			busy_until = $realtime + BUSY_NS;
			if (VERBOSE) $display("flash: programmed page %06x", page_addr);
		end else if (do_erase) begin
			for (i = 0; i < 4096; i = i + 1)
				mem[{addr[23:12], 12'h000} + i] = 8'hFF;
			wel = 0;
			busy_until = $realtime + BUSY_NS;
			if (VERBOSE) $display("flash: erased sector %06x", addr);
		end
		phase      = P_IGNORE;
		do_erase   = 0;
		do_program = 0;
	end

	// --- input: sample on the rising edge ----------------------------------------

	always @(posedge sck) if (!csb) begin
		if (out_en && (io0 === 1'bx || io1 === 1'bx))
			error("bus contention");

		if (phase == P_ADDR || phase == P_MODE ? dual_in : 0) begin
			shift_in = {shift_in[5:0], io1, io0};
			bits_in  = bits_in + 2;
		end else begin
			shift_in = {shift_in[6:0], io0};
			bits_in  = bits_in + 1;
		end

		if (bits_in == 8) begin
			bits_in = 0;
			byte_in(shift_in);
		end
	end

	task byte_in(input [7:0] b);
		begin
			case (phase)
				P_CMD: begin
					cmd = b;
					if (b != 8'hAB && b != 8'hFF && powered_down)
						error("command while in deep power-down");
					else if (b != 8'hFF && b != 8'hAB && $realtime < wake_time + TRES1_NS && wake_time != 0)
						error("command before tRES1 after ABh");
					else if (busy(0) && b != 8'h05)
						error("command while busy");
					case (b)
						8'h03, 8'hBB, 8'h20, 8'h02: begin
							phase     = P_ADDR;
							addr_bits = 0;
							dual_in   = b == 8'hBB;
						end
						8'h9F: begin
							phase    = P_ID;
							id_index = 0;
							start_out(JEDEC_ID[23:16], 0);
						end
						8'h05: begin
							phase = P_STATUS;
							start_out({6'd0, wel, busy(0)}, 0);
						end
						8'h06: begin wel = 1; phase = P_IGNORE; end
						8'h04: begin wel = 0; phase = P_IGNORE; end
						8'hB9: begin powered_down = 1; phase = P_IGNORE; end
						8'hAB: begin
							powered_down = 0;
							wake_time    = $realtime;
							phase        = P_IGNORE;
						end
						default: phase = P_IGNORE;
					endcase
				end

				P_ADDR: begin
					addr      = {addr[15:0], b};
					addr_bits = addr_bits + 8;
					if (addr_bits == 24) begin
						case (cmd)
							8'h03: begin phase = P_READ; start_out(mem[addr % SIZE], 0); end
							8'hBB: phase = P_MODE;
							8'h02: begin
								if (!wel) error("page program without write enable");
								do_program = wel;
								phase     = P_PROGRAM;
								page_addr = addr;
								for (i = 0; i < 256; i = i + 1) page_used[i] = 0;
							end
							8'h20: begin
								if (!wel) error("sector erase without write enable");
								do_erase = wel;
								phase    = P_IGNORE;
							end
						endcase
					end
				end

				P_MODE: begin
					mode_bits = b;
					crm       = b[5:4] === 2'b10;
					phase     = P_READ;
					start_out(mem[addr % SIZE], 1);
				end

				P_PROGRAM: begin
					page[page_addr[7:0]]      = b;
					page_used[page_addr[7:0]] = 1;
					page_addr[7:0]            = page_addr[7:0] + 1;
				end

				default: ;
			endcase
		end
	endtask

	// --- output: change on the falling edge -------------------------------------

	reg out_pending;

	task start_out(input [7:0] b, input dual);
		begin
			// the first bit appears at the next falling edge
			shift_out   = b;
			out_dual    = dual;
			bits_out    = 0;
			out_pending = 1;
		end
	endtask

	always @(negedge sck) if (!csb) begin
		if (out_pending) begin
			out_pending = 0;
			out_en      = 1;
		end else if (out_en) begin
			shift_out = out_dual ? {shift_out[5:0], 2'b00} : {shift_out[6:0], 1'b0};
			bits_out  = bits_out + (out_dual ? 2 : 1);
			if (bits_out == 8) begin
				case (phase)
					P_READ: begin
						addr = addr + 1;
						start_out(mem[addr % SIZE], out_dual);
						out_pending = 0;
					end
					P_ID: begin
						id_index = id_index + 1;
						start_out(id_index == 1 ? JEDEC_ID[15:8] : id_index == 2 ? JEDEC_ID[7:0] : 8'h00, 0);
						out_pending = 0;
					end
					P_STATUS: begin
						start_out({6'd0, wel, busy(0)}, 0);
						out_pending = 0;
					end
					default: out_en = 0;
				endcase
			end
		end
	end

endmodule
