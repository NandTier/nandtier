# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Pixel art of the launcher's game menu (fw/sdk/mkart.py)."""

KEY = ".kwbBcCyYrRgGpeF"

BG_PALETTES = [
    #  .      k      w      b      B      c      C      y      Y      r      R      g      G      p      e      F
    [0x012, 0x000, 0xFFF, 0x239, 0x46D, 0x0AC, 0x6EF, 0xC80, 0xFD3, 0xA22, 0xF55, 0x272, 0x5D5, 0x84C, 0x667, 0xFFF],
    [0x012, 0x000, 0xFFF, 0x239, 0x46D, 0x0AC, 0x6EF, 0xC80, 0xFD3, 0xA22, 0xF55, 0x272, 0x5D5, 0x84C, 0x667, 0xFD3],
    [0x012, 0x000, 0xFFF, 0x239, 0x46D, 0x0AC, 0x6EF, 0xC80, 0xFD3, 0xA22, 0xF55, 0x272, 0x5D5, 0x84C, 0x667, 0x6EF],
    [0x012, 0x000, 0xFFF, 0x239, 0x46D, 0x0AC, 0x6EF, 0xC80, 0xFD3, 0xA22, 0xF55, 0x272, 0x5D5, 0x84C, 0x667, 0x99A],
]

SPR_PALETTES = [
    [0x000, 0x000, 0xFFF, 0x239, 0x46D, 0x0AC, 0x6EF, 0xC80, 0xFD3, 0xA22, 0xF55, 0x272, 0x5D5, 0x84C, 0x667, 0xFFF],
    [0x000, 0x000, 0xFFF, 0x335, 0x557, 0x0AC, 0x6EF, 0xC80, 0xFD3, 0xA22, 0xF55, 0x272, 0x5D5, 0x84C, 0x889, 0xFFF],
]

TILES = {
    "frame_h": [
        "BBBBBBBB",
        "bbbbbbbb",
        "........",
        "........",
        "........",
        "........",
        "bbbbbbbb",
        "BBBBBBBB",
    ],
    "frame_v": [
        "Bb....bB",
        "Bb....bB",
        "Bb....bB",
        "Bb....bB",
        "Bb....bB",
        "Bb....bB",
        "Bb....bB",
        "Bb....bB",
    ],
    "frame_corner": [
        "BBBBBBBB",
        "BCCCCCCB",
        "BC.cc.CB",
        "BCcYYcCB",
        "BCcYYcCB",
        "BC.cc.CB",
        "BCCCCCCB",
        "BBBBBBBB",
    ],
    "bar_empty": [
        "eeeeeeee",
        "e.......",
        "e.......",
        "e.......",
        "e.......",
        "e.......",
        "e.......",
        "eeeeeeee",
    ],
    "bar_full": [
        "eeeeeeee",
        "GgGgGgGg",
        "gGgGgGgG",
        "GgGgGgGg",
        "gGgGgGgG",
        "GgGgGgGg",
        "gGgGgGgG",
        "eeeeeeee",
    ],
    "star_small": [
        "........",
        "........",
        "........",
        "...w....",
        "........",
        "........",
        "........",
        "........",
    ],
    "star_big": [
        "........",
        "...e....",
        "...w....",
        ".ewwwe..",
        "...w....",
        "...e....",
        "........",
        "........",
    ],
    "line": [
        "........",
        "........",
        "........",
        "pppppppp",
        "pppppppp",
        "........",
        "........",
        "........",
    ],
}

SPRITES = {
    "cursor": [
        "................",
        "....kk..........",
        "....kYkk........",
        "....kYYYkk......",
        "....kYYYYYkk....",
        "....kyYYYYYYkk..",
        "....kyyYYYYYYYk.",
        "....kyyyyYYYYYYk",
        "....kyyyyyyyyyyk",
        "....kyyyyyyyykk.",
        "....kcyyyyyykk..",
        "....kccyyykk....",
        "....kcccykk.....",
        "....kcckk.......",
        "....kkk.........",
        "................",
    ],
}
