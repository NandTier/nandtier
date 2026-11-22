# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Flappy Chip: pixel art (fw/sdk/mkart.py)."""

KEY = ".kwgGlyYoOrRbBnF"

#      .      k      w      g      G      l      y      Y      o      O      r      R      b      B      n      F
SKY = [0x6BE, 0x000, 0xFFF, 0x5C3, 0x272, 0xAE6, 0xFE4, 0xDA2, 0xF82, 0xC50, 0xE33, 0x822, 0xDEF, 0x9CD, 0xC96, 0xFFF]
BG_PALETTES = [SKY, SKY[:15] + [0xFE4], SKY[:15] + [0x222], SKY[:15] + [0xF82]]
SPR_PALETTES = [SKY]
BIG_FONT = True

TILES = {
    "pipe_l": ["kGgglllg", "kGgglllg", "kGgglllg", "kGgglllg", "kGgglllg", "kGgglllg", "kGgglllg", "kGgglllg"],
    "pipe_r": ["ggggGGGk", "ggggGGGk", "ggggGGGk", "ggggGGGk", "ggggGGGk", "ggggGGGk", "ggggGGGk", "ggggGGGk"],
    "cap_l": ["kkkkkkkk", "kGgllllg", "kGgllllg", "kGgllllg", "kGgglllg", "kGgggggg", "kGGGGGGG", "kkkkkkkk"],
    "cap_r": ["kkkkkkkk", "gggggGGk", "gggggGGk", "gggggGGk", "ggggGGGk", "ggggGGGk", "GGGGGGGk", "kkkkkkkk"],
    "grass": ["gglggglg", "gGgggGgg", "GGGGGGGG", "nnnnnnnn", "nYnnnnYn", "nnnnnnnn", "nnnYnnnn", "nnnnnnnn"],
    "dirt": ["nnnnnnnn", "nnYnnnnn", "nnnnnnYn", "nnnnnnnn", "Ynnnnnnn", "nnnnYnnn", "nnnnnnnn", "nnnnnnnY"],
    "cloud_l": ["........", "....wwww", "..wwwwww", ".wwwwwww", "wwwwwwww", "wwwwwwww", "bbbbbbbb", "........"],
    "cloud_r": ["........", "ww......", "wwww....", "wwwwww..", "wwwwwww.", "wwwwwwww", "bbbbbbbb", "........"],
    "bush": ["........", "........", "...ll...", "..llgl..", ".lgggggl", "lgggGggg", "gggGgggG", "GgGGGGgG"],
}

BIRD = [
    "................",
    "................",
    "......kkkkk.....",
    "....kkyyyyykk...",
    "...kyyyyyykwwk..",
    "..kyyyyyyykwkwk.",
    ".kyyyyyyyykwkwk.",
    "kyyyyyyyyyykwwk.",
    "kyyyyyyyyyykkkkk",
    "kyyyyyyyyykooooo",
    ".kyyyyyyyykoOOOk",
    "..kkkyyyyyykoook",
    "....kkYYYYYkkkk.",
    "......kkkkk.....",
    "................",
    "................",
]

WING = [
    "kwwwwk.",
    "kwwwwwk",
    "kbwwwwk",
    ".kbbbk.",
]


def bird(top):
    """the bird with its wing at rows top..top+3"""
    rows = [list(r) for r in BIRD]
    for y, line in enumerate(WING):
        for x, ch in enumerate(line):
            if ch != ".":
                rows[top + y][x] = ch
    return ["".join(r) for r in rows]


SPRITES = {"bird_up": bird(4), "bird_mid": bird(6), "bird_down": bird(8)}
