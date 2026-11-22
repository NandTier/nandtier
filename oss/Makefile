# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# The FPGA bitstream with open-source tools, no vendor software:
#
#   Gowin boards  Yosys (synth_gowin) -> nextpnr-himbaechel -> gowin_pack (Apicula)
#   ECP5 boards   Yosys (synth_ecp5)  -> nextpnr-ecp5       -> ecppack (Trellis)
#   then openFPGALoader
#
#   make [BOARD=<board>]    build/<board>/nandtier.fs (Gowin) or .bit (ECP5;
#                           ULX3S: build/ulx3s-<size>f/)
#   make load               load it into the FPGA (SRAM: lost at power-off)
#   make flash              write it to the board's configuration flash (stays);
#                           firmware and games further up in the flash stay too
#   make boards             build every board
#   make gatesim            Gowin boards: simulate the synthesised netlist with
#                           the Gowin primitive models (needs GOWIN_HOME)
#   make clean
#
# Boards (boards/<board>/board.mk):
#   tangnano9k   Sipeed Tang Nano 9K, Gowin GW1NR-9C (default)
#   tangnano20k  Sipeed Tang Nano 20K, Gowin GW2AR-18C
#   ulx3s        Radiona ULX3S, Lattice ECP5 (ULX3S_SIZE=12/25/45/85, default 85)
#
# The tools come in the YosysHQ OSS CAD Suite; point OSS_CAD at it, or put
# its bin/ on PATH and set OSS_CAD= (empty).
#
# hw/ is the same for every board; a board adds its top level (clocks,
# pins, polarity), its constraints and, where the vendor IP is not used,
# the portable RAMs of boards/common/nt_rams.v. The boot RAM gets the boot
# ROM from fw/fw-brom/build at synthesis.

BOARD   ?= tangnano9k
BOARDS   = tangnano9k tangnano20k ulx3s

NT_HERE := $(dir $(lastword $(MAKEFILE_LIST)))
# Tool locations written by setup/setup.sh or setup/setup.ps1 (see README,
# "Setting up"); a variable given on the command line or in the environment wins.
-include $(NT_HERE)../local.mk
OSS_CAD ?= $(abspath $(NT_HERE)../tools/oss-cad-suite)
BIN      = $(if $(OSS_CAD),$(OSS_CAD)/bin/)

YOSYS    = $(BIN)yosys
LOADER   = $(BIN)openFPGALoader

ROOT = ..
HW   = $(ROOT)/hw

ifeq ($(wildcard $(ROOT)/boards/$(BOARD)/board.mk),)
$(error unknown BOARD "$(BOARD)": choose one of $(BOARDS))
endif
include $(ROOT)/boards/$(BOARD)/board.mk

OUT ?= build/$(or $(BUILD_NAME),$(BOARD))

SRC = $(HW)/nandtier.v $(HW)/nandtier_core.v \
      $(wildcard $(HW)/core/*.v $(HW)/bus/*.v $(HW)/mem/*.v $(HW)/periph/*.v $(HW)/video/*.v) \
      $(addprefix $(ROOT)/,$(BOARD_SRC))
BROM = $(addprefix $(ROOT)/fw/fw-brom/build/fw-brom_,0.hex 1.hex 2.hex 3.hex)

.PHONY: all brom load flash boards gatesim clean

ifeq ($(VENDOR),gowin)
BITFILE = $(OUT)/nandtier.fs
SYNTH   = synth_gowin -top $(TOP) $(SYNTH_FLAGS)
else
BITFILE = $(OUT)/nandtier.bit
SYNTH   = synth_ecp5 -top $(TOP)
endif

all: $(BITFILE)

$(OUT):
	mkdir -p $@

brom:
	$(MAKE) -C $(ROOT)/fw/fw-brom

$(BROM): brom

# synthesis; the boot RAM's $readmemh files are looked up in the build
# directory. The few $buf cells Yosys may leave (the place-and-route tools
# have no place for them) become plain wires.
$(OUT)/nandtier.json: $(SRC) $(BROM) | $(OUT)
	cp $(BROM) $(OUT)/
	cd $(OUT) && $(YOSYS) -q -l yosys.log -p "read_verilog $(DEFINES) $(addprefix ../../,$(SRC)); \
		$(SYNTH); techmap t:\$$buf; opt_clean -purge; \
		write_json nandtier.json; tee -o stat.txt stat"

# --- Gowin ---------------------------------------------------------------------------

$(OUT)/nandtier_pnr.json: $(OUT)/nandtier.json $(ROOT)/$(CST) $(ROOT)/$(SDC)
	$(BIN)nextpnr-himbaechel --json $< --write $@ --device $(DEVICE) --vopt family=$(FAMILY) \
		--vopt cst=$(ROOT)/$(CST) --sdc $(ROOT)/$(SDC) --report $(OUT)/report.json \
		-l $(OUT)/nextpnr.log -q
	@grep -E "Max frequency for clock" $(OUT)/nextpnr.log | tail -3

# the SPI flash pins double as the configuration (MSPI) pins
$(OUT)/nandtier.fs: $(OUT)/nandtier_pnr.json
	$(BIN)gowin_pack -d $(FAMILY) $(PACK_FLAGS) -o $@ $< 2> $(OUT)/gowin_pack.log || \
		{ cat $(OUT)/gowin_pack.log; exit 1; }
	@echo "Bitstream for the $(BOARD_NAME): oss/$@"

# --- ECP5 ----------------------------------------------------------------------------

$(OUT)/nandtier.config: $(OUT)/nandtier.json $(ROOT)/$(LPF)
	$(BIN)nextpnr-ecp5 --json $< --textcfg $@ --$(ECP5_DEVICE) --package $(ECP5_PACKAGE) \
		--lpf $(ROOT)/$(LPF) --report $(OUT)/report.json -l $(OUT)/nextpnr.log -q
	@grep -E "Max frequency for clock" $(OUT)/nextpnr.log | tail -4

$(OUT)/nandtier.bit: $(OUT)/nandtier.config
	$(BIN)ecppack --compress $(ECPPACK_FLAGS) --input $< --bit $@
	@echo "Bitstream for the $(BOARD_NAME): oss/$@"

# --- programming ---------------------------------------------------------------------

load: $(BITFILE)
	$(LOADER) -b $(LOADER_BOARD) $<

flash: $(BITFILE)
	$(LOADER) -b $(LOADER_BOARD) -f $<

boards:
	for b in $(BOARDS); do $(MAKE) BOARD=$$b || exit 1; done

# --- gate-level simulation (Gowin boards) ---------------------------------------------

GOWIN_HOME ?= $(HOME)/gowin/IDE

ifeq ($(VENDOR),gowin)
GOWIN_SIM  = $(GOWIN_HOME)/simlib/$(if $(filter GW2A%,$(FAMILY)),gw2a,gw1n)/prim_sim.v
TB_DEFINES = $(if $(filter tangnano20k,$(BOARD)),-DTB_TANGNANO20K)

$(OUT)/gate.v: $(OUT)/nandtier.json
	$(YOSYS) -q -p "read_json $<; write_verilog -noattr $@"

# the Gowin rPLL model gives no clock in Icarus: rPLL and CLKDIV are
# simulated by sim_clocks.v instead, everything else by the Gowin models
$(OUT)/gate_sim.v: $(OUT)/gate.v
	sed -e 's/^\(  \)rPLL #(/\1nt_sim_rPLL #(/' -e 's/^\(  \)CLKDIV #(/\1nt_sim_CLKDIV #(/' $< > $@
	@grep -q nt_sim_rPLL $@ && grep -q nt_sim_CLKDIV $@

$(OUT)/tb_gate.vvp: tb_gate.v $(OUT)/gate_sim.v sim_clocks.v $(ROOT)/sim/spi_flash_model.v
	@test -f $(GOWIN_SIM) || { echo "Gowin simulation library not found: set GOWIN_HOME"; exit 1; }
	iverilog -g2012 -Wno-timescale $(TB_DEFINES) -s tb_gate -o $@ $^ $(GOWIN_SIM)

gatesim: $(OUT)/tb_gate.vvp
	vvp -n $< | tee $(OUT)/gatesim.log
	@grep -q '^PASS' $(OUT)/gatesim.log
else
gatesim:
	@echo "gatesim needs a Gowin board (the Gowin primitive models)"; exit 1
endif

clean:
	rm -rf build
