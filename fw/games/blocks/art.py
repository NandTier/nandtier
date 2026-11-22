# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Block Drop: pixel art (fw/sdk/mkart.py). Colour i is drawn with the
character KEY[i], so here simply its number in hex (2-F)."""

KEY = ".k23456789ABCDEF"

# palette 0: the seven pieces, a light and a dark shade each (2-3 I, 4-5 O,
# 6-7 T, 8-9 S, A-B Z, C-D J, E-F L); palettes 1-3: greys and text
PIECES = [0x102, 0x000, 0x6EF, 0x18A, 0xFE4, 0xB80, 0xD7F, 0x739, 0x7E7, 0x282,
          0xF66, 0x922, 0x69F, 0x23A, 0xFA4, 0xA50]
GREYS = [0x102, 0x000, 0xFFF, 0xBBC, 0x889, 0x556, 0x334, 0x223, 0x000, 0x000,
         0x000, 0x000, 0x000, 0x000, 0x000]
BG_PALETTES = [PIECES, GREYS + [0xFE4], GREYS + [0x6EF], GREYS + [0xAAB]]
SPR_PALETTES = [PIECES]
BIG_FONT = True


def cell(light, dark):
    """a block: light face, dark lower and right edges, black gap"""
    return [light * 7 + "k"] + [light * 6 + dark + "k"] * 5 + [light + dark * 6 + "k", "k" * 8]


TILES = {"cell%d" % i: cell("23456789ABCDEF"[2 * i], "23456789ABCDEF"[2 * i + 1]) for i in range(7)}
TILES.update({
    # palettes 1-3
    "wall": ["33333334", "34444445", "34444445", "34444445", "34444445", "34444445", "34444445", "45555555"],
    "ghost": ["44444444", "4......4", "4......4", "4......4", "4......4", "4......4", "4......4", "44444444"],
    "flash": ["22222222", "22222222", "22222222", "22222222", "22222222", "22222222", "22222222", "22222222"],
    "dots": ["........", "........", "........", "...6....", "........", "........", "........", "........"],
})
