# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Platformer levels, built from pieces.

A level is 14 blocks high (16 x 16 pixels each, below the 16-pixel status
bar) and up to 255 blocks wide. Row 0 is the top, the ground is rows 12-13.
"""

ROWS = 14

# block codes (index into BLOCK_ORDER in gen_assets.py)
SKY, GROUND_TOP, GROUND, BRICK, QUESTION, USED, STONE = range(7)
PIPE_TOP_L, PIPE_TOP_R, PIPE_L, PIPE_R, COIN = range(7, 12)
CLOUD_L, CLOUD_R, BUSH_L, BUSH_R, POLE, POLE_TOP = range(12, 18)


class Level:
    def __init__(self, name, width, night=False):
        self.name = name
        self.width = width
        self.night = night
        self.cells = [[SKY] * ROWS for _ in range(width)]   # [column][row]
        self.enemies = []                                   # columns, standing on the ground
        self.start = 2

    def set(self, col, row, code):
        self.cells[col][row] = code

    def ground(self, first, last, top=12):
        for c in range(first, last + 1):
            for r in range(top, ROWS):
                self.set(c, r, GROUND_TOP if r == top else GROUND)

    def row_of(self, col, row, pattern):
        """pattern: B brick, ? question, U used, S stone, o coin, space skip"""
        codes = {"B": BRICK, "?": QUESTION, "U": USED, "S": STONE, "o": COIN}
        for i, ch in enumerate(pattern):
            if ch != " ":
                self.set(col + i, row, codes[ch])

    def pipe(self, col, height, ground_row=12):
        top = ground_row - height
        self.set(col, top, PIPE_TOP_L)
        self.set(col + 1, top, PIPE_TOP_R)
        for r in range(top + 1, ground_row):
            self.set(col, r, PIPE_L)
            self.set(col + 1, r, PIPE_R)

    def cloud(self, col, row):
        self.set(col, row, CLOUD_L)
        self.set(col + 1, row, CLOUD_R)

    def bush(self, col, row=11):
        self.set(col, row, BUSH_L)
        self.set(col + 1, row, BUSH_R)

    def stairs_up(self, col, height, ground_row=12):
        for i in range(height):
            for r in range(ground_row - 1 - i, ground_row):
                self.set(col + i, r, STONE)

    def stairs_down(self, col, height, ground_row=12):
        for i in range(height):
            for r in range(ground_row - height + i, ground_row):
                self.set(col + i, r, STONE)

    def goal(self, col, ground_row=12):
        self.set(col, ground_row - 1, STONE)
        for r in range(2, ground_row - 1):
            self.set(col, r, POLE)
        self.set(col, 1, POLE_TOP)

    def enemy(self, *cols):
        self.enemies.extend(cols)

    def ascii(self):
        chars = " ##B?US[]{}oCcHh|T"
        return "\n".join("".join(chars[self.cells[c][r]] for c in range(self.width))
                         for r in range(ROWS))


def level_1():
    lv = Level("1-1", 180)
    lv.ground(0, 68)
    lv.ground(71, 85)
    lv.ground(89, 179)
    for c, r in ((8, 2), (19, 3), (36, 2), (56, 1), (75, 3), (95, 2), (120, 2), (140, 3), (160, 1)):
        lv.cloud(c, r)
    for c in (11, 24, 42, 60, 78, 101, 119, 144):
        lv.bush(c)
    lv.row_of(16, 8, "?")
    lv.row_of(20, 8, "B?B?B")
    lv.row_of(22, 4, "?")
    lv.pipe(28, 2)
    lv.pipe(38, 3)
    lv.pipe(46, 4)
    lv.pipe(57, 4)
    lv.row_of(64, 7, "oooo")
    lv.row_of(72, 9, "oooo")
    lv.row_of(77, 8, "B?B")
    lv.row_of(80, 4, "BBBBBBBB")
    lv.row_of(91, 4, "BBB?")
    lv.row_of(94, 8, "B")
    lv.row_of(100, 8, "BB")
    lv.row_of(106, 8, "?  ?  ?")
    lv.row_of(109, 4, "?")
    lv.row_of(118, 8, "B")
    lv.row_of(121, 4, "BBB")
    lv.row_of(128, 4, "B??B")
    lv.row_of(129, 8, "BB")
    lv.stairs_up(134, 4)
    lv.stairs_down(140, 4)
    lv.stairs_up(148, 8)
    lv.ground(156, 179)
    lv.goal(167)
    lv.enemy(22, 40, 51, 53, 80, 82, 97, 99, 114, 116, 124, 126, 128, 130)
    return lv


def level_2():
    lv = Level("1-2", 190, night=True)
    lv.ground(0, 25)
    lv.ground(29, 50)
    lv.ground(54, 56)
    lv.ground(60, 62)
    lv.ground(66, 100)
    lv.ground(104, 189)
    for c, r in ((6, 2), (30, 1), (52, 3), (80, 2), (110, 2), (135, 1), (165, 3)):
        lv.cloud(c, r)
    for c in (14, 36, 74, 90, 120, 150):
        lv.bush(c)
    lv.row_of(10, 8, "B?B")
    lv.row_of(17, 5, "?")
    lv.pipe(20, 3)
    lv.row_of(26, 8, "BBB")
    lv.row_of(26, 7, "ooo")
    lv.row_of(33, 8, "?B?B?")
    lv.pipe(42, 2)
    lv.stairs_up(46, 3)
    lv.row_of(51, 6, "BB")
    lv.row_of(54, 9, "ooo")
    lv.row_of(57, 7, "BB")
    lv.row_of(60, 9, "ooo")
    lv.row_of(63, 7, "BB")
    lv.pipe(70, 4)
    lv.row_of(76, 8, "BBBBBB")
    lv.row_of(76, 4, "B?B?B?")
    lv.row_of(77, 7, "oooo")
    lv.pipe(86, 3)
    lv.pipe(94, 5)
    lv.row_of(101, 6, "BB")
    lv.row_of(101, 5, "oo")
    lv.row_of(108, 8, "?")
    lv.row_of(112, 8, "BB?BB")
    lv.row_of(114, 4, "?")
    lv.stairs_up(124, 4)
    lv.stairs_down(130, 4)
    lv.row_of(138, 8, "SSSS")
    lv.row_of(144, 6, "SSSS")
    lv.row_of(145, 5, "oo")
    lv.stairs_up(158, 8)
    lv.goal(177)
    lv.enemy(14, 22, 34, 38, 44, 68, 73, 82, 84, 88, 112, 116, 118, 136, 140, 150, 152)
    return lv


LEVELS = [level_1(), level_2()]
