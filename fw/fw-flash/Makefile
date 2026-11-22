# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# User firmware ("the launcher"), runs from the start of the SPI flash.
# The games are separate cartridges (fw/games), which it loads from the SD
# card. Outputs in build/:
#   fw-flash.v    image for sw/nandtier-programmer.py and the simulation
#   fw-flash.elf, .bin, .asm, .map

NAME     = fw-flash
SRCS     = start.S main.c console.c tictactoe.c arcade.c loader.c sd.c ngame.c
LDSCRIPT = flash.ld
OPT      = -O2

SDK = ../sdk
EXTRA_CFLAGS = -I../common -I$(SDK) -Ibuild

vpath %.c ../common $(SDK)
vpath %.S ../common

include ../common.mk

.DEFAULT_GOAL := all
all: $(BUILD)/$(NAME).elf $(BUILD)/$(NAME).v $(BUILD)/$(NAME).bin $(BUILD)/$(NAME).asm

# the game menu's art
OBJS += $(BUILD)/art.c.o
$(BUILD)/$(NAME).elf: $(BUILD)/art.c.o

$(BUILD)/art.c $(BUILD)/art.h &: art.py $(SDK)/mkart.py ../../hw/video/gen_font.py | $(BUILD)
	$(PYTHON_NAME) $(SDK)/mkart.py art.py $(BUILD)/art.c $(BUILD)/art.h

$(BUILD)/art.c.o: $(BUILD)/art.c
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

$(BUILD)/arcade.c.o: $(BUILD)/art.h
