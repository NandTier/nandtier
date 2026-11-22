# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# All game cartridges, and the SD card pack the launcher loads them from:
#
#   make            build every game and build/carts.img (sw/mkcarts.py)
#   make clean
#
# A cartridge is a directory with a Makefile that includes ../../sdk/cart.mk
# (see fw/sdk). To add one, add "<directory>:<NAME ON THE MENU>" below
# (underscores become spaces, up to 16 characters, up to 15 games).

CARTS = hopper:NANDTIER_HOPPER \
        snake:SNAKE \
        bricks:BRICK_BREAKER \
        invaders:ALIEN_RAID \
        pong:PONG \
        blocks:BLOCK_DROP \
        flappy:FLAPPY_CHIP \
        racer:ROAD_RUSH

PYTHON_NAME ?= python3

DIRS = $(foreach c,$(CARTS),$(word 1,$(subst :, ,$(c))))

.PHONY: all clean $(DIRS)

all: build/carts.img

$(DIRS):
	$(MAKE) -C $@

build/carts.img: $(DIRS) ../../sw/mkcarts.py
	mkdir -p build
	$(PYTHON_NAME) ../../sw/mkcarts.py $@ \
		$(foreach c,$(CARTS),"$(subst _, ,$(word 2,$(subst :, ,$(c))))=$(word 1,$(subst :, ,$(c)))/build/$(word 1,$(subst :, ,$(c))).bin")
	$(PYTHON_NAME) ../../sw/mkcarts.py --list $@

clean:
	for d in $(DIRS); do $(MAKE) -C $$d clean; done
	rm -rf build
