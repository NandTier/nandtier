# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Pong: pixel art (fw/sdk/mkart.py)."""

KEY = ".kwgGcCrRyYeEbBF"

#        .      k      w      g      G      c      C      r      R      y      Y      e      E      b      B      F
TABLE = [0x031, 0x000, 0xFFF, 0x3A4, 0x163, 0x5DF, 0x28B, 0xF55, 0xA22, 0xFE4, 0xC80, 0x8B8, 0xCEC, 0x042, 0x020, 0xFFF]
BG_PALETTES = [
    TABLE,
    TABLE[:15] + [0xFE4],
    TABLE[:15] + [0x5DF],
    TABLE[:15] + [0x4A6],         # dim (the big score digits)
]
SPR_PALETTES = [TABLE]
BIG_FONT = True

TILES = {
    "net": ["......ee", "......EE", "......ee", "......EE", "........", "........", "........", "........"],
    "wall": ["eeeeeeee", "EEEEEEEE", "EwEEEEEw", "EEEEEEEE", "eeeeeeee", "bbbbbbbb", "........", "........"],
    "wall_b": ["........", "........", "bbbbbbbb", "eeeeeeee", "EEEEEEEE", "EwEEEEEw", "EEEEEEEE", "eeeeeeee"],
    "line": ["..b.....", "..b.....", "..b.....", "..b.....", "..b.....", "..b.....", "..b.....", "..b....."],
    "pad_top": [".cccccc.", "cwwwwwwc", "cwCCCCCc", "cCCCCCCc", "cCCCCCCc", "cCCCCCCc", "cCCCCCCc", "cCCCCCCc"],
    "pad_mid": ["cCCCCCCc", "cCCCCCCc", "cCCwCCCc", "cCCCCCCc", "cCCCCCCc", "cCCwCCCc", "cCCCCCCc", "cCCCCCCc"],
    "pad_top2": [".rrrrrr.", "rwwwwwwr", "rwRRRRRr", "rRRRRRRr", "rRRRRRRr", "rRRRRRRr", "rRRRRRRr", "rRRRRRRr"],
    "pad_mid2": ["rRRRRRRr", "rRRRRRRr", "rRRwRRRr", "rRRRRRRr", "rRRRRRRr", "rRRwRRRr", "rRRRRRRr", "rRRRRRRr"],
    "ball": ["..yyy...", ".ywwyy..", "yywyyyY.", "yyyyyyY.", "yyyyyYY.", ".YYYYY..", "..YYY...", "........"],
}
