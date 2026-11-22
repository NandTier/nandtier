# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Radiona ULX3S: Lattice ECP5 (12F, 25F, 45F or 85F: ULX3S_SIZE), 25 MHz
# oscillator, GPDI (HDMI), SD card slot, SPI flash shared with the
# bitstream (firmware at 0x200000), UART through the FTDI USB bridge.

ULX3S_SIZE  ?= 85

BOARD_NAME   = Radiona ULX3S ($(ULX3S_SIZE)F)
BUILD_NAME   = ulx3s-$(ULX3S_SIZE)f
VENDOR       = ecp5
TOP          = nt_ulx3s
BOARD_SRC    = boards/ulx3s/top.v boards/common/ecp5_hdmi_phy.v boards/common/nt_rams.v
DEFINES      = -DNT_HDMI_PHY_EXTERNAL

# the 12F is a 25F die with its own ID code
ECP5_DEVICE  = $(if $(filter 12,$(ULX3S_SIZE)),25k,$(ULX3S_SIZE)k)
ECPPACK_FLAGS = $(if $(filter 12,$(ULX3S_SIZE)),--idcode 0x21111043)
ECP5_PACKAGE = CABGA381
LPF          = boards/ulx3s/ulx3s.lpf

LOADER_BOARD = ulx3s
FLASH_OFFSET = 0x200000
