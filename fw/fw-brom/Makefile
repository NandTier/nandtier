# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Boot ROM image. Outputs in build/:
#   fw-brom.elf, .asm, .map
#   fw-brom_0..3.mi    Gowin memory init files, one per byte lane, for
#                      sw/update_bootram_init.py
#   fw-brom_0..3.hex   the same for $readmemh (simulation)

NAME     = fw-brom
SRCS     = start.S isp.c sd.c
LDSCRIPT = brom.ld
OPT      = -Os

# flash_io() also runs with the user firmware's gp: no gp-relative accesses
EXTRA_CFLAGS  = -msmall-data-limit=0 -I../common
EXTRA_LDFLAGS = -Wl,--no-relax

vpath %.c ../common

include ../common.mk

.DEFAULT_GOAL := all
all: $(BUILD)/$(NAME).elf $(BUILD)/$(NAME).asm $(BUILD)/$(NAME)_0.mi

$(BUILD)/$(NAME)_0.mi: $(BUILD)/$(NAME).v ../../sw/mem_image.py
	$(PYTHON_NAME) ../../sw/mem_image.py $< 0x80000000 8192 $(BUILD)/$(NAME)
