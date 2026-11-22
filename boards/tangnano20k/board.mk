# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Sipeed Tang Nano 20K: Gowin GW2AR-18C, 27 MHz crystal, HDMI (true LVDS),
# TF card slot, 8 MiB SPI flash shared with the bitstream (firmware at
# 0x100000), UART through the BL616 USB bridge.

BOARD_NAME   = Sipeed Tang Nano 20K
VENDOR       = gowin
TOP          = nt_tangnano20k
BOARD_SRC    = boards/tangnano20k/top.v boards/common/nt_rams.v

DEVICE       = GW2AR-LV18QN88C8/I7
FAMILY       = GW2A-18C
SYNTH_FLAGS  = -family gw2a
CST          = boards/tangnano20k/tangnano20k.cst
SDC          = boards/tangnano20k/tangnano20k.sdc
PACK_FLAGS   = --mspi_as_gpio

LOADER_BOARD = tangnano20k
FLASH_OFFSET = 0x100000
