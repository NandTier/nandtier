// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier UART: 8 data bits, no parity, 1 stop bit, with a programmable
// bit period and a 16-byte receive FIFO (FIFO_BITS). The FIFO lets the
// software look away for 16 byte times (about 35,000 cycles at 115200
// baud) without losing a byte.
//
// Registers:
//   +0x0 DATA  read:  oldest received byte in bits 7:0 (and removes it),
//                     or 0xFFFF_FFFF when nothing has been received
//              write: send bits 7:0; the bus access waits while the
//                     previous byte is still being sent
//   +0x4 DIV   bit period in clock cycles, 16 bits (minimum 4)
//
// The bus answers in the same cycle (ready is combinational), except for
// a DATA write while the transmitter is busy.

`timescale 1 ns / 1 ps

module nt_uart #(
	parameter [15:0] DEFAULT_DIV = 16'd217,  // 115200 baud at 25 MHz
	parameter        FIFO_BITS   = 4         // receive FIFO: 2^FIFO_BITS bytes
) (
	input             clk,
	input             resetn,

	input             valid,
	input      [31:0] addr,
	input      [31:0] wdata,
	input      [ 3:0] wstrb,
	output            ready,
	output     [31:0] rdata,

	input             rx,
	output reg        tx
);
	reg [15:0] div;

	wire sel_div  = addr[2];
	wire is_write = |wstrb;

	// --- transmitter ---------------------------------------------------------

	reg [ 9:0] tx_shift;    // stop bit, 8 data bits, start bit (sent LSB first)
	reg [ 3:0] tx_bits;     // bits left to send, 0 = idle
	reg [15:0] tx_count;

	wire tx_busy  = tx_bits != 4'd0;
	wire tx_write = valid && !sel_div && wstrb[0];

	always @(posedge clk) begin
		if (!resetn) begin
			tx       <= 1'b1;
			tx_bits  <= 4'd0;
		end else if (tx_write && !tx_busy) begin
			tx_shift <= {1'b1, wdata[7:0], 1'b0};
			tx_bits  <= 4'd10;
			tx_count <= 16'd0;
		end else if (tx_busy) begin
			tx <= tx_shift[0];
			if (tx_count == div - 16'd1) begin
				tx_count <= 16'd0;
				tx_shift <= {1'b1, tx_shift[9:1]};
				tx_bits  <= tx_bits - 4'd1;
			end else begin
				tx_count <= tx_count + 16'd1;
			end
		end else begin
			tx <= 1'b1;
		end
	end

	// --- receiver ------------------------------------------------------------

	reg [ 2:0] rx_sync;     // synchroniser and edge detector
	reg [ 3:0] rx_bits;     // 0 = idle, else bits left including the stop bit
	reg [15:0] rx_count;
	reg [ 7:0] rx_shift;
	reg        rx_push;

	wire rx_in = rx_sync[1];

	always @(posedge clk) begin
		rx_sync <= {rx_sync[1:0], rx};
		rx_push <= 1'b0;

		if (!resetn) begin
			rx_sync <= 3'b111;
			rx_bits <= 4'd0;
		end else if (rx_bits == 4'd0) begin
			// start bit: wait half a bit period, then sample in the middle
			if (rx_sync[2] && !rx_in) begin
				rx_bits  <= 4'd10;
				rx_count <= {1'b0, div[15:1]};
			end
		end else if (rx_count != 16'd0) begin
			rx_count <= rx_count - 16'd1;
		end else begin
			rx_count <= div - 16'd1;
			rx_bits  <= rx_bits - 4'd1;
			case (rx_bits)
				4'd10:   if (rx_in) rx_bits <= 4'd0;   // glitch, not a start bit
				4'd1:    rx_push <= rx_in;             // keep it only with a valid stop bit
				default: rx_shift <= {rx_in, rx_shift[7:1]};
			endcase
		end
	end

	// --- receive FIFO ----------------------------------------------------------

	reg [7:0] fifo [0:(1 << FIFO_BITS) - 1];
	reg [FIFO_BITS:0] fifo_head, fifo_tail;     // one extra bit tells full from empty

	wire fifo_empty = fifo_head == fifo_tail;
	wire fifo_full  = fifo_head == {~fifo_tail[FIFO_BITS], fifo_tail[FIFO_BITS-1:0]};
	wire rx_pop     = valid && !sel_div && !is_write && !fifo_empty;

	always @(posedge clk) begin
		if (!resetn) begin
			fifo_head <= 0;
			fifo_tail <= 0;
		end else begin
			if (rx_push && !fifo_full) begin
				fifo[fifo_head[FIFO_BITS-1:0]] <= rx_shift;
				fifo_head <= fifo_head + 1'b1;
			end
			if (rx_pop)
				fifo_tail <= fifo_tail + 1'b1;
		end
	end

	// --- bus -------------------------------------------------------------------

	always @(posedge clk) begin
		if (!resetn)
			div <= DEFAULT_DIV;
		else if (valid && sel_div) begin
			if (wstrb[0]) div[ 7:0] <= wdata[ 7:0];
			if (wstrb[1]) div[15:8] <= wdata[15:8];
		end
	end

	assign ready = valid && !(tx_write && tx_busy);
	assign rdata = sel_div    ? {16'd0, div} :
	               fifo_empty ? 32'hFFFF_FFFF :
	                            {24'd0, fifo[fifo_tail[FIFO_BITS-1:0]]};

endmodule
