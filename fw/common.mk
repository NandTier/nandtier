# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# Build rules shared by fw/fw-brom, fw/fw-flash and the game cartridges
# (fw/sdk/cart.mk). A project Makefile sets NAME, SRCS, LDSCRIPT and
# optionally OPT and EXTRA_CFLAGS, then includes this file.
#
#   RISCV_PATH, RISCV_NAME  toolchain root and prefix (as in the top Makefile)

# fw/, wherever the including Makefile is
NT_HERE := $(dir $(lastword $(MAKEFILE_LIST)))
FW := $(patsubst %/,%,$(NT_HERE))

# Tool locations written by setup/setup.sh or setup/setup.ps1 (see README,
# "Setting up"); a variable given on the command line or in the environment wins.
-include $(NT_HERE)../local.mk

RISCV_NAME  ?= riscv-none-elf
RISCV_PATH  ?= $(abspath $(NT_HERE)../tools/riscv-gcc)
PYTHON_NAME ?= python3

CC      = $(RISCV_PATH)/bin/$(RISCV_NAME)-gcc
OBJCOPY = $(RISCV_PATH)/bin/$(RISCV_NAME)-objcopy
OBJDUMP = $(RISCV_PATH)/bin/$(RISCV_NAME)-objdump

# The core is RV32I only: no M (mul/div) and no C (compressed) extension.
# GCC 12 and later want the CSR instructions (rdcycle) named as Zicsr; older
# compilers (riscv-none-embed 8.x) do not know the name, so ask the compiler.
ZICSR  := $(shell $(CC) -march=rv32i_zicsr -mabi=ilp32 -E -x c /dev/null >/dev/null 2>&1 && echo _zicsr)
ARCH    = -march=rv32i$(ZICSR) -mabi=ilp32
OPT    ?= -O2

CFLAGS  = $(ARCH) $(OPT) -g -std=gnu11 -Wall -Wextra -ffreestanding -fno-builtin \
          -ffunction-sections -fdata-sections -I$(FW)/include $(EXTRA_CFLAGS)
LDFLAGS = $(ARCH) -nostdlib -nostartfiles -Wl,--gc-sections -Wl,-T,$(LDSCRIPT) \
          -Wl,-Map,$(BUILD)/$(NAME).map -Wl,--print-memory-usage $(EXTRA_LDFLAGS)

BUILD = build
OBJS  = $(addprefix $(BUILD)/,$(addsuffix .o,$(SRCS)))

.PHONY: all clean
.SECONDARY:

$(BUILD)/$(NAME).elf: $(OBJS) $(LDSCRIPT)
	$(CC) $(LDFLAGS) -o $@ $(OBJS) -lgcc

$(BUILD)/%.v: $(BUILD)/%.elf
	$(OBJCOPY) -O verilog $< $@

$(BUILD)/%.bin: $(BUILD)/%.elf
	$(OBJCOPY) -O binary $< $@

$(BUILD)/%.asm: $(BUILD)/%.elf
	$(OBJDUMP) -d -S $< > $@

$(BUILD)/%.c.o: %.c | $(BUILD)
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

$(BUILD)/%.S.o: %.S | $(BUILD)
	$(CC) $(CFLAGS) -MMD -c -o $@ $<

$(BUILD):
	mkdir -p $@

clean:
	rm -rf $(BUILD)

-include $(OBJS:.o=.d)
