# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Snake: pixel art (fw/sdk/mkart.py)."""

KEY = ".kwgGlrRyYbBepsF"

#        .      k      w      g      G      l      r      R      y      Y      b      B      e      p      s      F
GAME = [0x131, 0x000, 0xFFF, 0x2B2, 0x070, 0x8E6, 0xE22, 0x811, 0xFE4, 0xC80, 0x963, 0x641, 0x777, 0xF9A, 0x243, 0xFFF]
BG_PALETTES = [
    GAME,
    GAME[:15] + [0xFE4],                                    # yellow text
    GAME[:3] + [0x999, 0x555, 0xCCC] + GAME[6:15] + [0xF66],   # dead snake: grey, red text
    GAME[:15] + [0x9C9],                                    # pale text
]
SPR_PALETTES = [GAME]
BIG_FONT = True

TILES = {
    "wall": [
        "bbbBbbbB",
        "bbbBbbbB",
        "BBBBBBBB",
        "bBbbbBbb",
        "bBbbbBbb",
        "BBBBBBBB",
        "bbbBbbbB",
        "BBBBBBBB",
    ],
    "tuft": [
        "........",
        "........",
        "..s.....",
        "..s.s...",
        "........",
        ".....s..",
        "....s.s.",
        "........",
    ],
    "body": [
        "..GGGG..",
        ".GggggG.",
        "GgllggGG",
        "GglgggGG",
        "GggggGGG",
        "GggggGGG",
        ".GGGGGG.",
        "..GGGG..",
    ],
    "head_r": [
        ".GGGG...",
        "GgggwkG.",
        "GllgwkgG",
        "GlgggggG",
        "GggggggG",
        "GgggwkgG",
        "GgggwkG.",
        ".GGGG...",
    ],
    "head_u": [
        "..GGGG..",
        ".GgggggG",
        "GggggggG",
        "GwwggwwG",
        "GkkggkkG",
        "GgggggGG",
        "GlggggGG",
        "GGGGGGG.",
    ],
    "apple": [
        "....G...",
        "...G....",
        ".rrRrr..",
        "rwrrrrr.",
        "rwrrrrR.",
        "rrrrrrR.",
        ".rrrrR..",
        "..RRR...",
    ],
    "gold": [
        "....G...",
        "...G....",
        ".yyYyy..",
        "ywyyyyy.",
        "ywyyyyY.",
        "yyyyyyY.",
        ".yyyyY..",
        "..YYY...",
    ],
}
