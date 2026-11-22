# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Road Rush: pixel art (fw/sdk/mkart.py). Traffic cars are the player's car
drawn with other sprite palettes (colours r/R)."""

KEY = ".kwgGlrReEaAyYbF"

#         .      k      w      g      G      l      r      R      e      E      a      A      y      Y      b      F
ROAD = [0x444, 0x000, 0xFFF, 0x2A3, 0x172, 0x8D5, 0xE22, 0x811, 0x666, 0x999, 0x444, 0x333, 0xFE4, 0xC80, 0x8CF, 0xFFF]
BG_PALETTES = [ROAD, ROAD[:15] + [0xFE4], ROAD[:15] + [0x8CF], ROAD[:15] + [0xF66]]


def car(body, dark):
    p = list(ROAD)
    p[0] = 0x000
    p[6], p[7] = body, dark
    return p


SPR_PALETTES = [car(0xE22, 0x811), car(0x37E, 0x139), car(0xFC2, 0xA70), car(0xEEE, 0x888)]
BIG_FONT = True

TILES = {
    "asphalt": ["aaaaaaaa", "aaaaaaaa", "aaaaAaaa", "aaaaaaaa", "aaaaaaaa", "aaaaaaaa", "Aaaaaaaa", "aaaaaaaa"],
    "lane": ["wwaaaaaa", "wwaaaaaa", "wwaaaaaa", "wwaaaaaa", "wwaaaaaa", "wwaaaaaa", "wwaaaaaa", "wwaaaaaa"],
    "kerb_r": ["rrrrrrrr", "rrrrrrrr", "rrrrrrrr", "rrrrrrrr", "RRRRRRRR", "RRRRRRRR", "RRRRRRRR", "RRRRRRRR"],
    "kerb_w": ["wwwwwwww", "wwwwwwww", "wwwwwwww", "wwwwwwww", "EEEEEEEE", "EEEEEEEE", "EEEEEEEE", "EEEEEEEE"],
    # grass: g is the lawn, G darker tufts
    "grass": ["gggggggg", "gggGgggg", "gggggggg", "ggggggGg", "gggggggg", "gGgggggg", "gggggggg", "ggggGggg"],
    "tree": ["gggllggg", "ggllllgg", "glllllGg", "lllllGGG", "glllGGGg", "ggGGGGgg", "gggRRggg", "gggRRggg"],
    "bush": ["gggggggg", "gggggggg", "gglllggg", "glllllGg", "lllllGGG", "GGGGGGGG", "gggggggg", "gggggggg"],
    "flag_r": ["rrrrrrrr", "rwrwrwrw", "wrwrwrwr", "rwrwrwrw", "wrwrwrwr", "rrrrrrrr", "........", "........"],
}

SPRITES = {
    "car": [
        "....kkkkkkkk....",
        "...krrrrrrrrk...",
        "..kkrRwwwwRrkk..",
        "..kkrbbbbbbrkk..",
        "...krbbbbbbrk...",
        "...krrrrrrrrk...",
        "...krrrRRrrrk...",
        "...krrrRRrrrk...",
        "...krrrRRrrrk...",
        "..kkrrrrrrrrkk..",
        "..kkrbbbbbbrkk..",
        "..kkrRRRRRRrkk..",
        "...krrrrrrrrk...",
        "...kyrrrrrryk...",
        "....kkkkkkkk....",
        "................",
    ],
    "smoke": [
        "................",
        "......eeE.......",
        "....eEEEEe......",
        "...eEEwwEEe.....",
        "..eEwwwwwEEe....",
        "..eEwwwwwwEe.ee.",
        "...eEwwwwEe.eEEe",
        "....eEEEEe..eEwe",
        ".....eeee...eEEe",
        "..ee.........ee.",
        ".eEEe...eee.....",
        ".eEwe..eEEEe....",
        "..ee...eEwEe....",
        "........eee.....",
        "................",
        "................",
    ],
}
