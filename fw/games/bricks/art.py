# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Brick Breaker: pixel art (fw/sdk/mkart.py). A brick is two tiles; its
colour comes from the palette: four background palettes, four colours."""

KEY = ".kwhmdeEbBcCyYsF"

# h/m/d: brick highlight, middle, dark (set per palette); e/E wall greys
def brick(h, m, d, text=0xFFF):
    return [0x112, 0x000, 0xFFF, h, m, d, 0x667, 0xAAB, 0x235, 0x123, 0x3CF, 0x18A, 0xFE4, 0xC80, 0x445, text]

BG_PALETTES = [
    brick(0xF88, 0xE33, 0x922),                 # red
    brick(0xFD8, 0xEA2, 0x962, 0xFE4),          # orange, yellow text
    brick(0x8F8, 0x3C3, 0x272, 0x8CF),          # green, blue text
    brick(0x8CF, 0x38E, 0x249, 0x99A),          # blue, grey text
]
SPR_PALETTES = [
    [0x000, 0x000, 0xFFF, 0xF88, 0xE33, 0x922, 0x667, 0xAAB, 0x235, 0x123, 0x3CF, 0x18A, 0xFE4, 0xC80, 0x445, 0xFFF],
]
BIG_FONT = True

TILES = {
    "brick_l": [
        "hhhhhhhh",
        "hmmmmmmm",
        "hmmmmmmm",
        "hmmmmmmm",
        "hmmmmmmm",
        "hmmmmmmm",
        "dddddddd",
        "kkkkkkkk",
    ],
    "brick_r": [
        "hhhhhhhk",
        "mmmmmmdk",
        "mmmmmmdk",
        "mmmmmmdk",
        "mmmmmmdk",
        "mmmmmmdk",
        "dddddddk",
        "kkkkkkkk",
    ],
    "steel_l": [
        "EEEEEEEE",
        "EwEEEEEE",
        "EEeeeeee",
        "EEeEEEEE",
        "EEeEEEEE",
        "EEeEEEEE",
        "eeeeeeee",
        "kkkkkkkk",
    ],
    "steel_r": [
        "EEEEEEEk",
        "EEEEEEek",
        "eeeeeeek",
        "EEEEEEek",
        "EEEEEEek",
        "EEEEEwek",
        "eeeeeeek",
        "kkkkkkkk",
    ],
    "wall_v": [
        "eEEEEEEe",
        "eEwEEEEe",
        "eEEEEEEe",
        "eEEEEEEe",
        "eEEEEEEe",
        "eEEEEEEe",
        "eEEEEEee",
        "eeeeeeee",
    ],
    "wall_h": [
        "eeeeeeee",
        "EEEEEEEE",
        "EwEEEEEE",
        "EEEEEEEE",
        "EEEEEEEE",
        "EEEEEEEE",
        "eeeeeeee",
        "kkkkkkkk",
    ],
    "back": [
        "b.......",
        "........",
        "........",
        "........",
        "....b...",
        "........",
        "........",
        "........",
    ],
    "pad_l": [
        "..cccccc",
        ".cwwwwww",
        "cwCCCCCC",
        "cCCCCCCC",
        "cCCCCCCC",
        ".CCCCCCC",
        "..CCCCCC",
        "........",
    ],
    "pad_m": [
        "yyyyyyyy",
        "wwwwwwww",
        "yyyyyyyy",
        "YYYYYYYY",
        "YYYYYYYY",
        "YYYYYYYY",
        "YYYYYYYY",
        "........",
    ],
    "ball": [
        "........",
        "..www...",
        ".wwwwE..",
        ".wwwwE..",
        ".wwEEE..",
        "..EEE...",
        "........",
        "........",
    ],
    "life": [
        "........",
        "........",
        ".cyyyyc.",
        "cwwwwwwc",
        "cCYYYYCc",
        ".cyyyyc.",
        "........",
        "........",
    ],
}
