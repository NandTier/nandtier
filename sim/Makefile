# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Whole-SoC simulation (tb_soc.v): the real boot ROM and user firmware on
# hw/nandtier.v, with sim/spi_flash_model.v as the flash.
#
#   make            boot into the firmware, use its menu (several minutes)
#   make offset     the firmware test with the firmware at flash address
#                   0x200000 (FLASH_OFFSET, as on the Tang Nano 20K / ULX3S)
#   make isp        boot ROM ISP: ping, erase, program, restart
#   make carts      the game menu on the RTL: Pong from the SD card model into
#                   the flash cartridge slot and running (tens of minutes);
#                   its first frame must match the PC build's (test/host)
#   make clean
#
# Needs the Gowin primitive simulation library from the Gowin IDE:
#   GOWIN_HOME=<IDE install directory>, containing simlib/gw1n/prim_sim.v

NT_HERE := $(dir $(lastword $(MAKEFILE_LIST)))
# Tool locations written by setup/setup.sh or setup/setup.ps1 (see README,
# "Setting up"); a variable given on the command line or in the environment wins.
-include $(NT_HERE)../local.mk

GOWIN_HOME ?= $(HOME)/gowin/IDE
GOWIN_SIM   = $(GOWIN_HOME)/simlib/gw1n/prim_sim.v

ROOT = ..
HW   = $(ROOT)/hw
OUT  = build

SRC = tb_soc.v spi_flash_model.v sd_card_model.v gowin_clocks_sim.v \
      $(HW)/nandtier.v $(HW)/nandtier_core.v \
      $(wildcard $(HW)/core/*.v $(HW)/bus/*.v $(HW)/mem/*.v $(HW)/periph/*.v $(HW)/video/*.v) \
      $(ROOT)/gowin_ip/sram_2kx8/sram_2kx8.v \
      $(wildcard $(ROOT)/project/src/gowin_sp/bootram_2kx8_?.v)

FW = $(ROOT)/fw/fw-brom/build/fw-brom_0.hex $(ROOT)/fw/fw-flash/build/fw-flash.v

.PHONY: all firmware offset isp carts fw clean

all: firmware

$(OUT):
	mkdir -p $@

$(OUT)/tb_soc.vvp: $(SRC) | $(OUT)
	@test -f $(GOWIN_SIM) || { echo "Gowin simulation library not found: set GOWIN_HOME"; exit 1; }
	iverilog -g2012 -Wno-timescale -s tb_soc -o $@ $(SRC) $(GOWIN_SIM)

fw:
	$(MAKE) -C $(ROOT)/fw/fw-brom
	$(MAKE) -C $(ROOT)/fw/fw-flash
	$(MAKE) -C $(ROOT)/fw/games

# the cartridge pack as $(readmemh) bytes for sd_card_model.v
$(OUT)/carts.hex: fw | $(OUT)
	python3 $(ROOT)/sw/mkcarts.py --hex $@ $(ROOT)/fw/games/build/carts.img

PONG_HOST = $(ROOT)/test/build/host/pong

firmware: $(OUT)/tb_soc.vvp fw $(OUT)/carts.hex
	vvp -n $< | tee $(OUT)/firmware.log
	@grep -q '^PASS' $(OUT)/firmware.log

$(OUT)/tb_soc_offset.vvp: $(SRC) | $(OUT)
	@test -f $(GOWIN_SIM) || { echo "Gowin simulation library not found: set GOWIN_HOME"; exit 1; }
	iverilog -g2012 -Wno-timescale -s tb_soc -P tb_soc.FLASH_OFFSET=24\'h200000 -o $@ $(SRC) $(GOWIN_SIM)

offset: $(OUT)/tb_soc_offset.vvp fw $(OUT)/carts.hex
	vvp -n $< | tee $(OUT)/offset.log
	@grep -q '^PASS' $(OUT)/offset.log

isp: $(OUT)/tb_soc.vvp fw $(OUT)/carts.hex
	vvp -n $< +isp | tee $(OUT)/isp.log
	@grep -q '^PASS' $(OUT)/isp.log

carts: $(OUT)/tb_soc.vvp fw $(OUT)/carts.hex
	$(MAKE) -C $(ROOT)/test build/host/pong
	vvp -n $< +carts | tee $(OUT)/carts.log
	@grep -q '^PASS' $(OUT)/carts.log
	$(PONG_HOST) 3 $(OUT)/pong_host 2 > /dev/null
	python3 compare_ppm.py $(OUT)/carts_pong.ppm $(OUT)/pong_host_0002.ppm

clean:
	rm -rf $(OUT)
