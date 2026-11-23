# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# NandTier top-level build
#
#   make              build the boot ROM and the user firmware
#   make brom         boot ROM only   (fw/fw-brom/build)
#   make flash        user firmware, the launcher   (fw/fw-flash/build)
#   make games        the game cartridges and their SD card pack
#                     (fw/games/build/carts.img)
#   make bootram      write the boot ROM into the boot RAM initial values
#                     (project/src/gowin_sp); then rebuild the bitstream
#   make program      in one go over the UART: the launcher into the flash and
#                     the games onto the SD card (card in the board's slot)
#                       COMx=<serial port>  [PROG_FILE=<objcopy verilog file>]
#                       [CARTS=<pack>, or CARTS= to leave the SD card alone]
#                       [SD_IMAGE=<file> SD_START_BLOCK=2048 SD_MAX_SECTORS=<n>]
#   make program-games  only the games onto the SD card
#   make fpga         FPGA bitstream with the open-source tools, for BOARD
#                     (oss/build/<board>/); see oss/Makefile
#   make fpga-load    load it into the FPGA (until power-off)  [openFPGALoader]
#   make fpga-flash   write it to the FPGA's configuration flash (permanent)
#
# BOARD=tangnano9k (default), tangnano20k or ulx3s (boards/): picks the
# bitstream and where `make program` puts the firmware in the flash.
#   make test         the test suite in test/
#   make sim          the whole-SoC simulation in sim/
#   make site         the documentation website (site/ -> docs/, GitHub Pages)
#   make clean

NT_HERE := $(dir $(lastword $(MAKEFILE_LIST)))
# Tool locations written by setup/setup.sh or setup/setup.ps1 (see README,
# "Setting up"); a variable given on the command line or in the environment wins.
-include $(NT_HERE)local.mk

PYTHON_NAME ?= python3
RISCV_NAME  ?= riscv-none-elf
RISCV_PATH  ?= $(abspath $(NT_HERE)tools/riscv-gcc)

FW_FILE         = fw/fw-flash/build/fw-flash.v
PROG_FILE      ?= $(FW_FILE)
COMx           ?= /dev/ttyUSB1
SD_IMAGE       ?=
BOARD          ?= tangnano9k
FLASH_OFFSET    = $(shell sed -n 's/^FLASH_OFFSET *= *//p' boards/$(BOARD)/board.mk)
CARTS_FILE      = fw/games/build/carts.img
CARTS          ?= $(CARTS_FILE)
SD_START_BLOCK ?= 2048
SD_MAX_SECTORS ?=

export PYTHON_NAME RISCV_NAME RISCV_PATH

.PHONY: all brom flash games bootram program program-games fpga fpga-load fpga-flash test sim site clean

all: brom flash games

brom:
	$(MAKE) -C fw/fw-brom

flash:
	$(MAKE) -C fw/fw-flash

games:
	$(MAKE) -C fw/games

$(FW_FILE): flash
$(CARTS_FILE): games

bootram: brom
	$(PYTHON_NAME) sw/update_bootram_init.py

program: $(PROG_FILE) $(CARTS)
	$(PYTHON_NAME) sw/nandtier-programmer.py --flash-offset $(FLASH_OFFSET) $(if $(CARTS),--carts $(CARTS)) \
		$(PROG_FILE) $(COMx) \
		$(if $(SD_IMAGE),$(SD_IMAGE) $(SD_START_BLOCK) $(SD_MAX_SECTORS))

program-games: $(CARTS_FILE)
	$(PYTHON_NAME) sw/nandtier-programmer.py --no-firmware --carts $(CARTS_FILE) $(PROG_FILE) $(COMx)

fpga:
	$(MAKE) -C oss BOARD=$(BOARD)

fpga-load:
	$(MAKE) -C oss BOARD=$(BOARD) load

fpga-flash:
	$(MAKE) -C oss BOARD=$(BOARD) flash

test:
	$(MAKE) -C test

sim:
	$(MAKE) -C sim

site:
	$(PYTHON_NAME) site/build.py

clean:
	$(MAKE) -C fw/fw-brom clean
	$(MAKE) -C fw/fw-flash clean
	$(MAKE) -C fw/games clean
	$(MAKE) -C oss clean
	$(MAKE) -C test clean
	$(MAKE) -C sim clean
