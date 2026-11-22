# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Sipeed Tang Nano 9K: Gowin GW1NR-9C, 27 MHz crystal, HDMI (emulated
# LVDS), TF card slot, 4 MiB SPI flash (free for the firmware: the
# bitstream lives inside the FPGA), UART through the BL702 USB bridge.

BOARD_NAME   = Sipeed Tang Nano 9K
VENDOR       = gowin
TOP          = nandtier
BOARD_SRC    = boards/tangnano9k/gowin_ip.v boards/common/nt_rams.v

DEVICE       = GW1NR-LV9QN88PC6/I5
FAMILY       = GW1N-9C
SYNTH_FLAGS  =
CST          = boards/tangnano9k/tangnano9k.cst
SDC          = boards/tangnano9k/tangnano9k.sdc
PACK_FLAGS   = --mspi_as_gpio

LOADER_BOARD = tangnano9k
FLASH_OFFSET = 0x000000
