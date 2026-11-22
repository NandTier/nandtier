// Copyright 2026 Abdul Muheet Ghani
// SPDX-License-Identifier: Apache-2.0
//
// NandTier SoC: memory map and peripheral registers (see hw/nandtier.v).

#ifndef NANDTIER_H
#define NANDTIER_H

#include <stdint.h>

#define NT_CLK_HZ       24975000u       // 27 MHz * 37 / 8 / 5
#define NT_UART_BAUD    115200u

// --- memory map ----------------------------------------------------------------

#define NT_FLASH_BASE   0x00000000u     // SPI flash, execute in place
#define NT_SRAM_BASE    0x40000000u     // 8 KiB
#define NT_SRAM_SIZE    0x2000u
#define NT_BOOT_BASE    0x80000000u     // boot RAM, 8 KiB, reset vector
#define NT_FLASHCFG     0x81000000u
#define NT_GPIO_BASE    0x82000000u
#define NT_UART_BASE    0x83000000u
#define NT_SDSPI_BASE   0xC0000000u
#define NT_PPU_BASE     0xC1000000u
#define NT_ILA_BASE     0xC2000000u     // 64 B, CPU bus trace analyzer

#define NT_REG(addr)    (*(volatile uint32_t *)(addr))
#define NT_REG8(addr)   (*(volatile uint8_t *)(addr))

// --- UART ------------------------------------------------------------------------

#define UART_DATA       NT_REG(NT_UART_BASE + 0x0)    // read: byte or 0xFFFFFFFF if none
#define UART_DIV        NT_REG(NT_UART_BASE + 0x4)    // bit period in clock cycles

// --- on-chip logic analyzer ------------------------------------------------------
//
// Captures 128 CPU bus clock samples. Each record contains the bus address,
// the transaction's read or write data, and bus-control flags.

#define ILA_CTRL         NT_REG(NT_ILA_BASE + 0x00)   // write: bit 0 arm, bit 1 address trigger
#define ILA_TRIGGER_ADDR NT_REG(NT_ILA_BASE + 0x04)
#define ILA_TRIGGER_MASK NT_REG(NT_ILA_BASE + 0x08)
#define ILA_POST_COUNT   NT_REG(NT_ILA_BASE + 0x0C)   // samples after trigger (0..255)
#define ILA_READ_INDEX   NT_REG(NT_ILA_BASE + 0x10)   // chronological sample index (0..127)
#define ILA_SAMPLE0      NT_REG(NT_ILA_BASE + 0x14)   // bus address
#define ILA_SAMPLE1      NT_REG(NT_ILA_BASE + 0x18)   // bus write data or read data
#define ILA_SAMPLE2      NT_REG(NT_ILA_BASE + 0x1C)   // flags

#define ILA_CTRL_ARM           0x01u
#define ILA_CTRL_TRIGGER_ADDR  0x02u
#define ILA_STATUS_ARMED       0x01u
#define ILA_STATUS_DONE        0x02u
#define ILA_STATUS_TRIGGERED   0x04u
#define ILA_STATUS_COUNT_SHIFT 8
#define ILA_STATUS_COUNT_MASK  0x0000FF00u
#define ILA_SAMPLE_READY       0x01u
#define ILA_SAMPLE_VALID       0x02u
#define ILA_SAMPLE_WSTRB_SHIFT 2
#define ILA_SAMPLE_INSTR       0x40u
#define ILA_SAMPLE_TRAP        0x80u

// --- GPIO ------------------------------------------------------------------------

#define GPIO_OUT        NT_REG(NT_GPIO_BASE + 0x0)
#define GPIO_IN         NT_REG(NT_GPIO_BASE + 0x4)
#define GPIO_OE         NT_REG(NT_GPIO_BASE + 0x8)

// --- SPI flash config register -------------------------------------------------
//
// Byte-wide access keeps the other fields: byte 0 = bit-bang pins, byte 1 =
// bit-bang output enables, byte 2 = read mode, byte 3 = XIP enable.

#define FLASHCFG        NT_REG(NT_FLASHCFG)
#define FLASHCFG_PINS   NT_REG8(NT_FLASHCFG + 0)
#define FLASHCFG_OE     NT_REG8(NT_FLASHCFG + 1)
#define FLASHCFG_MODE   NT_REG8(NT_FLASHCFG + 2)
#define FLASHCFG_EN     NT_REG8(NT_FLASHCFG + 3)

#define FLASH_PIN_IO0   0x01            // MOSI
#define FLASH_PIN_IO1   0x02            // MISO
#define FLASH_PIN_CLK   0x10
#define FLASH_PIN_CSB   0x20
#define FLASH_OE_IO0    0x01
#define FLASH_MODE_CRM  0x10            // bit 20: continuous read mode
#define FLASH_MODE_DUAL 0x40            // bit 22: dual I/O reads
#define FLASH_EN_XIP    0x80            // bit 31

// --- SD card SPI port ----------------------------------------------------------------

#define SD_TX           NT_REG(NT_SDSPI_BASE + 0x0)
#define SD_RX           NT_REG(NT_SDSPI_BASE + 0x4)
#define SD_CTRL         NT_REG(NT_SDSPI_BASE + 0x8)
#define SD_DIV          NT_REG(NT_SDSPI_BASE + 0xC)

#define SD_CTRL_SCK     0x01
#define SD_CTRL_MOSI    0x02
#define SD_CTRL_CS      0x04
#define SD_CTRL_MISO    0x08
#define SD_CTRL_BUSY    0x10

// --- picture processing unit (hw/video/nt_ppu.v) ------------------------------------
//
// Offsets from NT_PPU_BASE. Video memory is write only.

#define PPU_CTRL        0x0000          // bit 0 background, 1 sprites, 2 text terminal
#define PPU_SCROLL_X    0x0004          // 0..511
#define PPU_SCROLL_Y    0x0008          // 0..255
#define PPU_SPLIT       0x000C          // lines above this are not scrolled
#define PPU_STATUS      0x0010          // bit 0 vertical blank, bits 31:16 frame count
#define PPU_PALETTE     0x0400          // 128 x 0x0RGB: 0..63 background, 64..127 sprites
#define PPU_OAM         0x0800          // 64 sprites
#define PPU_NAMETAB     0x2000          // 64 x 32 tile map, entry = row * 64 + column
#define PPU_CHR         0x4000          // 256 tiles x 8 rows, 8 x 4-bit pixels per word

#define PPU_CTRL_BG     0x1
#define PPU_CTRL_SPR    0x2
#define PPU_CTRL_TERM   0x4

#define PPU_REG(off)    NT_REG(NT_PPU_BASE + (off))

// tile map entry
#define NT_ENTRY(tile, pal, hflip, vflip) \
	((tile) | ((pal) << 8) | ((hflip) << 10) | ((vflip) << 11))

// sprite: y = top line, x = -256..255
#define OAM_ENTRY(y, x, tile, pal, hflip, vflip, big, behind) \
	(((y) & 0xFF) | (((x) & 0x1FF) << 8) | ((tile) << 17) | ((pal) << 25) | \
	 ((hflip) << 27) | ((vflip) << 28) | ((big) << 29) | ((behind) << 30))
#define OAM_HIDDEN      0xF0            // y of an unused sprite

// --- boot ROM services ---------------------------------------------------------------
//
// flash_io(buf, len, wren): one SPI flash command with XIP switched off, run
// from boot RAM. Sends buf[0..len-1] and overwrites it with the bytes read
// back. With wren set, write-enable (06h) goes first and it waits for the
// flash to finish (status bit 0) afterwards.

#define NT_BOOT_FLASH_IO   (NT_BOOT_BASE + 0x54)

typedef void (*nt_flash_io_fn)(uint8_t *buf, int len, int wren);
#define nt_flash_io ((nt_flash_io_fn)NT_BOOT_FLASH_IO)

// --- game cartridges -----------------------------------------------------------------
//
// The games live on the SD card as a cartridge pack (sw/mkcarts.py), and
// the user firmware (fw/fw-flash, "the launcher") copies the selected one
// into the cartridge slot of the SPI flash, from where it runs in place.
//
//   flash 0x000000  launcher            flash 0x100000  cartridge slot (1 MiB)
//   SD block NT_CART_SD_BLOCK: directory, then the game images (see sw/mkcarts.py)

#define NT_CART_SLOT        0x00100000u
#define NT_CART_SLOT_SIZE   0x00100000u
#define NT_CART_SD_BLOCK    8192u           // 4 MiB into the card
#define NT_CART_MAX         15

// The last 16 bytes of the SRAM pass a message between the launcher and a
// game across the jump (startup code and stack stay below them).

struct nt_handoff {
	uint32_t magic;                 // NT_HANDOFF_MAGIC
	uint32_t check;                 // ~magic ^ cmd
	uint32_t cmd;
	uint32_t arg;                   // cartridge number
};

#define NT_HANDOFF          ((volatile struct nt_handoff *)(NT_SRAM_BASE + NT_SRAM_SIZE - 16))
#define NT_HANDOFF_MAGIC    0x4E544846u     // "NTHF"
#define NT_HANDOFF_PLAY     1               // launcher -> game
#define NT_HANDOFF_RETURN   2               // game -> launcher: open the game menu again

static inline void nt_handoff_set(uint32_t cmd, uint32_t arg)
{
	NT_HANDOFF->magic = NT_HANDOFF_MAGIC;
	NT_HANDOFF->check = ~NT_HANDOFF_MAGIC ^ cmd;
	NT_HANDOFF->cmd   = cmd;
	NT_HANDOFF->arg   = arg;
}

// cmd of a valid message, else 0 (e.g. random SRAM contents after power-up)
static inline uint32_t nt_handoff_cmd(void)
{
	uint32_t cmd = NT_HANDOFF->cmd;
	if (NT_HANDOFF->magic != NT_HANDOFF_MAGIC || NT_HANDOFF->check != (~NT_HANDOFF_MAGIC ^ cmd))
		return 0;
	return cmd;
}

// --- CPU -------------------------------------------------------------------------------

static inline uint32_t nt_cycles(void)
{
	uint32_t c;
	__asm__ volatile ("rdcycle %0" : "=r"(c));
	return c;
}

static inline uint32_t nt_instret(void)
{
	uint32_t n;
	__asm__ volatile ("rdinstret %0" : "=r"(n));
	return n;
}

#endif
