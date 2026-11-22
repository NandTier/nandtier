# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Build rules for a game cartridge (fw/games/<game>/Makefile). The game's
# Makefile sets NAME and SRCS (its own sources) and includes this file;
# with an art.py next to it, mkart.py turns that into build/art.c and
# build/art.h (#include "art.h").
#
# Outputs in build/:
#   <NAME>.bin    the cartridge image, linked for the flash cartridge slot;
#                 sw/mkcarts.py packs these for the SD card
#   <NAME>.elf, .asm, .map

SDK := $(patsubst %/,%,$(dir $(lastword $(MAKEFILE_LIST))))

NO_NGAME ?=
SRCS     += start.S cart.c $(if $(NO_NGAME),,ngame.c cart_main.c)
LDSCRIPT  = $(SDK)/cart.ld
OPT      ?= -O2

ART = $(wildcard art.py)
EXTRA_CFLAGS += -I$(SDK) -I$(SDK)/../common -Ibuild

vpath %.c $(SDK) $(SDK)/../common
vpath %.S $(SDK)/../common

include $(SDK)/../common.mk

.DEFAULT_GOAL := all
all: $(BUILD)/$(NAME).elf $(BUILD)/$(NAME).bin $(BUILD)/$(NAME).asm

ifneq ($(ART),)
OBJS += $(BUILD)/art.c.o
$(BUILD)/$(NAME).elf: $(BUILD)/art.c.o

$(BUILD)/art.c $(BUILD)/art.h &: art.py $(SDK)/mkart.py | $(BUILD)
	$(PYTHON_NAME) $(SDK)/mkart.py art.py $(BUILD)/art.c $(BUILD)/art.h

$(BUILD)/art.c.o: $(BUILD)/art.c
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

# every object may include art.h
$(filter-out $(BUILD)/art.c.o,$(OBJS)): $(BUILD)/art.h

art: $(BUILD)/art.c $(BUILD)/art.h
.PHONY: art
endif
