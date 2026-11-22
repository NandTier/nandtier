# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# NandTier test suite
#
#   make            run every test below
#   make unit       one testbench per CPU core module (hw/core/)
#   make periph     UART, GPIO, SPI flash, SD SPI, ILA/JTAG CPU debug and bus decoder
#   make video      TMDS encoder, video timing, text terminal, PPU, ECP5 HDMI output
#   make core       ISA, C and trap programs on nandtier_core, several bus latencies
#   make random     random programs on nandtier_core, checked against the
#                   instruction set simulator core/rv32i_iss.py
#                   (SEEDS="1 2 3", N=<instructions per program>)
#   make sw         sw/nandtier-programmer.py against a simulated boot ROM
#   make game       the platformer's rules, on a PC build with a PPU model
#   make games      every game cartridge on the PC build: plays them with
#                   scripted controls, checks their rules, saves screenshots
#   make carts      the cartridge loader's CRC and the SD cartridge pack format
#   make fw         build both firmware images
#   make clean
#
# The whole-SoC simulation is in ../sim (make -C ../sim).
# Needs iverilog, python3 and the RISC-V toolchain from the top-level Makefile.

NT_HERE := $(dir $(lastword $(MAKEFILE_LIST)))
# Tool locations written by setup/setup.sh or setup/setup.ps1 (see README,
# "Setting up"); a variable given on the command line or in the environment wins.
-include $(NT_HERE)../local.mk

RISCV_NAME ?= riscv-none-elf
RISCV_PATH ?= $(abspath $(NT_HERE)../tools/riscv-gcc)

CC      = $(RISCV_PATH)/bin/$(RISCV_NAME)-gcc
OBJCOPY = $(RISCV_PATH)/bin/$(RISCV_NAME)-objcopy
OBJDUMP = $(RISCV_PATH)/bin/$(RISCV_NAME)-objdump

# Zicsr/Zifencei must be named for GCC 12 and later (see fw/common.mk)
ZICSR  := $(shell $(CC) -march=rv32im_zicsr_zifencei -mabi=ilp32 -E -x c /dev/null >/dev/null 2>&1 && echo _zicsr_zifencei)
CFLAGS  = -march=rv32im$(ZICSR) -mabi=ilp32 -O2 -ffreestanding -nostdlib -nostartfiles \
          -T core/link.ld -Wl,--gc-sections
IVERILOG = iverilog -g2012 -Wall -Wno-timescale

HW  = ../hw
OUT = build

CORE_SRC = $(HW)/nandtier_core.v $(wildcard $(HW)/core/*.v)

UNITS      = alu branch decode lsu regfile csr muldiv
TRAP_CASES = 1 2 3 4 5 6 7 8 9 10 11 12 13 14 15 16
SEEDS     ?= $(shell seq 1 20)
N         ?= 1000

PERIPH_TESTS = tb_uart tb_gpio tb_spi_flash tb_flash_cache tb_sd_spi tb_ila tb_jtag_ila tb_cpu_debug tb_bus_mux4
VIDEO_TESTS  = tb_tmds tb_video_timing tb_text_term tb_ppu tb_ecp5_phy

.PHONY: all unit periph video core random sw game games carts bus fw clean isa c trap latency \
        $(addprefix unit-,$(UNITS)) $(addprefix trap-,$(TRAP_CASES)) \
        $(addprefix random-,$(SEEDS)) $(PERIPH_TESTS) $(VIDEO_TESTS)

# keep generated programs, ELFs and disassembly for debugging
.SECONDARY:

all: unit periph video core random sw game games carts fw
	@echo "=== all NandTier tests done ==="

$(OUT):
	mkdir -p $@

# Run a simulation, keep its log, and turn a missing PASS line into a make
# error: $(call run_sim,<vvp>,<log name>,<plusargs>)
define run_sim
	vvp -n $(1) $(3) | tee $(OUT)/$(2).log
	@grep -q '^PASS' $(OUT)/$(2).log
endef

# --- CPU core module tests ---------------------------------------------------------

unit: $(addprefix unit-,$(UNITS))

$(OUT)/tb_%.vvp: unit/tb_%.v $(wildcard $(HW)/core/*.v) | $(OUT)
	$(IVERILOG) -s tb_$* -o $@ $^

$(addprefix unit-,$(UNITS)): unit-%: $(OUT)/tb_%.vvp
	@echo "=== unit: nt_$* ==="
	$(call run_sim,$<,unit_$*)

# --- peripherals and video ---------------------------------------------------------

periph: $(PERIPH_TESTS)
video: $(VIDEO_TESTS)


$(OUT)/tb_uart.vvp:         periph/tb_uart.v $(HW)/periph/nt_uart.v
$(OUT)/tb_gpio.vvp:         periph/tb_gpio.v $(HW)/periph/nt_gpio.v
$(OUT)/tb_spi_flash.vvp:    periph/tb_spi_flash.v $(HW)/periph/nt_spi_flash.v ../sim/spi_flash_model.v
$(OUT)/tb_flash_cache.vvp:  periph/tb_flash_cache.v $(HW)/periph/nt_flash_cache.v $(HW)/periph/nt_spi_flash.v \
                            ../sim/spi_flash_model.v
$(OUT)/tb_sd_spi.vvp:       periph/tb_sd_spi.v $(HW)/periph/nt_sd_spi.v
$(OUT)/tb_ila.vvp:           periph/tb_ila.v $(HW)/periph/nt_ila.v
$(OUT)/tb_jtag_ila.vvp:      periph/tb_jtag_ila.v $(HW)/periph/nt_jtag_ila.v
$(OUT)/tb_cpu_debug.vvp:     periph/tb_cpu_debug.v $(HW)/nandtier_core.v $(wildcard $(HW)/core/*.v) \
                             $(HW)/periph/nt_cpu_debug.v $(HW)/periph/nt_jtag_ila.v
$(OUT)/tb_bus_mux4.vvp:     bus/tb_bus_mux4.v $(HW)/bus/nt_bus_mux4.v
$(OUT)/tb_tmds.vvp:         video/tb_tmds.v $(HW)/video/nt_tmds_encoder.v
$(OUT)/tb_video_timing.vvp: video/tb_video_timing.v $(HW)/video/nt_video_timing.v
$(OUT)/tb_text_term.vvp:    video/tb_text_term.v $(HW)/video/nt_text_term.v $(HW)/video/nt_font_rom.v
$(OUT)/tb_ppu.vvp:          video/tb_ppu.v $(HW)/video/nt_ppu.v $(HW)/video/nt_video_timing.v
$(OUT)/tb_ecp5_phy.vvp:     video/tb_ecp5_phy.v ../boards/common/ecp5_hdmi_phy.v

$(addprefix $(OUT)/,$(addsuffix .vvp,$(PERIPH_TESTS) $(VIDEO_TESTS))): | $(OUT)
	$(IVERILOG) -s $(basename $(notdir $@)) -o $@ $^

$(PERIPH_TESTS) $(VIDEO_TESTS): %: $(OUT)/%.vvp
	@echo "=== $* ==="
	$(call run_sim,$<,$*)

bus: tb_bus_mux4

# --- core programs -------------------------------------------------------------------

core: isa c trap latency

$(OUT)/tb_core.vvp: core/tb_core.v core/tb_mem.v $(CORE_SRC) | $(OUT)
	$(IVERILOG) -s tb_core -o $@ $^

$(OUT)/test_isa.elf: core/test_isa.S core/link.ld | $(OUT)
	$(CC) $(CFLAGS) -o $@ core/test_isa.S

$(OUT)/test_trap_%.elf: core/test_trap.S core/link.ld | $(OUT)
	$(CC) $(CFLAGS) -DCASE=$* -o $@ core/test_trap.S

$(OUT)/test_c.elf: core/start.S core/test_c.c core/link.ld | $(OUT)
	$(CC) $(CFLAGS) -o $@ core/start.S core/test_c.c -lgcc

$(OUT)/%.hex: $(OUT)/%.elf
	$(OBJCOPY) -O verilog $< $@
	$(OBJDUMP) -d $< > $(OUT)/$*.asm

isa: $(OUT)/tb_core.vvp $(OUT)/test_isa.hex
	@echo "=== core: RV32I instruction test ==="
	$(call run_sim,$<,test_isa,+hex=$(OUT)/test_isa.hex)

c: $(OUT)/tb_core.vvp $(OUT)/test_c.hex
	@echo "=== core: C program test ==="
	$(call run_sim,$<,test_c,+hex=$(OUT)/test_c.hex)

trap: $(addprefix trap-,$(TRAP_CASES))

$(addprefix trap-,$(TRAP_CASES)): trap-%: $(OUT)/tb_core.vvp $(OUT)/test_trap_%.hex
	@echo "=== core: trap case $* ==="
	$(call run_sim,$<,test_trap_$*,+hex=$(OUT)/test_trap_$*.hex +expect_trap)

# same programs with a same-cycle ready, slow memory and random wait states
latency: $(OUT)/tb_core.vvp $(OUT)/test_isa.hex $(OUT)/test_c.hex
	@echo "=== core: bus latency variants ==="
	$(call run_sim,$<,test_isa_lat0,+hex=$(OUT)/test_isa.hex +lat=0)
	$(call run_sim,$<,test_isa_lat4,+hex=$(OUT)/test_isa.hex +lat=4)
	$(call run_sim,$<,test_isa_rand,+hex=$(OUT)/test_isa.hex +rand_lat)
	$(call run_sim,$<,test_c_lat0,+hex=$(OUT)/test_c.hex +lat=0)
	$(call run_sim,$<,test_c_rand,+hex=$(OUT)/test_c.hex +rand_lat)

# --- random programs vs the instruction set simulator ----------------------------------

random: $(addprefix random-,$(SEEDS))

$(OUT)/random_%.S: core/gen_random.py | $(OUT)
	python3 core/gen_random.py $* $(N) > $@

$(OUT)/random_%.elf: $(OUT)/random_%.S core/link.ld
	$(CC) $(CFLAGS) -o $@ $<

$(addprefix random-,$(SEEDS)): random-%: $(OUT)/tb_core.vvp $(OUT)/random_%.hex core/rv32i_iss.py
	@echo "=== random: seed $* ==="
	$(call run_sim,$<,random_$*_rtl,+hex=$(OUT)/random_$*.hex +rand_lat +storelog=$(OUT)/random_$*.stores)
	python3 core/rv32i_iss.py $(OUT)/random_$*.hex $(OUT)/random_$*.stores

# --- host tools ------------------------------------------------------------------------------

sw:
	@echo "=== sw: nandtier-programmer ==="
	python3 sw/test_programmer.py

# --- the games on the PC ------------------------------------------------------------------
#
# The PPU model (host/ppu_model.c) stands in for hw/video/nt_ppu.v.

GAMES_DIR = ../fw/games
SDK       = ../fw/sdk
HOST_CC   = gcc -O2 -Wall -Wextra -DGAME_HOST -I../fw/include -I$(SDK) -Ihost
HOPPER    = $(GAMES_DIR)/hopper
NG_GAMES  = snake bricks invaders pong blocks flappy racer

$(HOPPER)/game_assets.c $(HOPPER)/build/game_gfx.bin: $(wildcard $(HOPPER)/assets/*.py)
	$(MAKE) -C $(HOPPER) game_assets.c build/game_gfx.bin

$(OUT)/host/game_host: host/game_host.c host/ppu_model.c host/ppu_model.h $(HOPPER)/game.c $(HOPPER)/game.h \
		$(SDK)/game_hal.h $(HOPPER)/game_assets.c | $(OUT)
	mkdir -p $(OUT)/host
	$(HOST_CC) -I$(HOPPER) -o $@ host/game_host.c host/ppu_model.c $(HOPPER)/game.c $(HOPPER)/game_assets.c

game: $(OUT)/host/game_host $(HOPPER)/build/game_gfx.bin
	@echo "=== game: NandTier Hopper rules ==="
	python3 host/test_game.py $(OUT)/host/game_host $(HOPPER)/build/game_gfx.bin $(OUT)/host

# an ngame cartridge: its sources, the art from its Makefile, the library
.SECONDEXPANSION:
$(addprefix $(OUT)/host/,$(NG_GAMES)): $(OUT)/host/%: $$(wildcard $(GAMES_DIR)/%/*.c $(GAMES_DIR)/%/*.h $(GAMES_DIR)/%/*.py) \
		host/ng_host.c host/ppu_model.c host/ppu_model.h $(SDK)/ngame.c $(SDK)/ngame.h \
		$(SDK)/mkart.py | $(OUT)
	mkdir -p $(OUT)/host
	$(MAKE) -C $(GAMES_DIR)/$* art $$(test -f $(GAMES_DIR)/$*/maps.py && echo maps)
	$(HOST_CC) -I$(GAMES_DIR)/$*/build -o $@ host/ng_host.c host/ppu_model.c $(SDK)/ngame.c \
		$(wildcard $(GAMES_DIR)/$*/*.c) $(GAMES_DIR)/$*/build/art.c \
		$$(test -f $(GAMES_DIR)/$*/maps.py && echo $(GAMES_DIR)/$*/build/maps.c)

games: $(addprefix $(OUT)/host/,$(NG_GAMES))
	@echo "=== games: every cartridge on the PC build ==="
	python3 host/test_games.py $(OUT)/host

# --- cartridge loader and pack -----------------------------------------------------------

$(OUT)/host/loader_host: host/loader_host.c host/loader_host.h ../fw/fw-flash/loader.c ../fw/fw-flash/loader.h | $(OUT)
	mkdir -p $(OUT)/host
	gcc -O2 -Wall -Wextra -DLOADER_HOST -I../fw/include -I../fw/common -I../fw/fw-flash -Ihost -o $@ \
		host/loader_host.c ../fw/fw-flash/loader.c

carts: $(OUT)/host/loader_host
	@echo "=== carts: cartridge pack and loader ==="
	python3 host/test_carts.py $(OUT)/host/loader_host $(OUT)/host

# --- firmware ----------------------------------------------------------------------------------

fw:
	@echo "=== firmware build ==="
	$(MAKE) -C ../fw/fw-brom RISCV_NAME=$(RISCV_NAME) RISCV_PATH=$(RISCV_PATH)
	$(MAKE) -C ../fw/fw-flash RISCV_NAME=$(RISCV_NAME) RISCV_PATH=$(RISCV_PATH)
	$(MAKE) -C ../fw/games RISCV_NAME=$(RISCV_NAME) RISCV_PATH=$(RISCV_PATH)

clean:
	rm -rf $(OUT)
