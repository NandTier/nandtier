#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Game rules of NandTier Hopper, checked on the PC build (game_host).

    test_game.py <game_host> <gfx_pack.bin> <work dir>

Instead of fixed frame numbers (which change whenever the physics are
tuned), the stomp and block tests search for a jump timing that works.
"""

import os
import re
import subprocess
import sys

MODES = "TITLE PLAY DYING CLEAR GAME_OVER WIN".split()
RIGHT, START, RUN, JUMP = 0x01, 0x10, 0x20, 0x40

host, pack, work = sys.argv[1:4]
failures = []


def run(frames, script, shots="", col=None, level=0, use_pack=False):
    env = dict(os.environ, GAME_START_LEVEL=str(level))
    env.pop("GAME_START_COL", None)
    if col:
        env["GAME_START_COL"] = str(col)
    prefix = os.path.join(work, "shot")
    out = subprocess.run([host, str(frames), prefix, shots, script, pack if use_pack else ""],
                         capture_output=True, text=True, env=env, check=True).stdout
    m = re.search(r"mode (\d+), level (\d+), hero x (-?\d+) y (-?\d+), camera (\d+), "
                  r"score (\d+), coins (\d+), lives (\d+), time (-?\d+)", out)
    r = dict(zip("mode level x y cam score coins lives time".split(), map(int, m.groups())))
    r["mode"] = MODES[r["mode"]]
    return r


def check(ok, what, detail=""):
    print("  %s: %s %s" % ("ok" if ok else "FAILED", what, detail))
    if not ok:
        failures.append(what)


def jumps(first, last, every=45, length=25):
    return ";".join("%d-%d:%d" % (f, f + length, JUMP) for f in range(first, last, every))


START_GAME = "30-31:%d" % START

r = run(20, "")
check(r["mode"] == "TITLE", "title screen", r["mode"])

found = [j for j in range(60, 260, 2)
         if (lambda r: r["score"] >= 100 and r["mode"] == "PLAY")(
             run(420, "%s;40-420:%d;%d-%d:%d" % (START_GAME, RIGHT, j, j + 14, JUMP)))]
check(found, "stomping a slime scores and keeps the hero alive", "(%d jump timings)" % len(found))

found = [j for j in range(60, 220, 2)
         if run(300, "%s;40-%d:%d;%d-%d:%d" % (START_GAME, j, RIGHT, j + 1, j + 14, JUMP))["coins"] >= 1]
check(found, "hitting a ? block gives a coin", "(%d jump timings)" % len(found))

r = run(200, "%s;40-200:%d" % (START_GAME, RIGHT), col=66)
check(r["mode"] == "DYING" and r["lives"] == 3, "falling into a pit", r["mode"])

r = run(1100, "%s;40-1100:%d" % (START_GAME, RIGHT))
check(r["mode"] == "GAME_OVER" and r["lives"] == 0, "three deaths: game over", r["mode"])

r = run(900, "%s;40-900:%d;%s" % (START_GAME, RIGHT, jumps(60, 900)), col=160)
check(r["mode"] == "PLAY" and r["level"] == 1 and r["score"] > 0, "flag pole of 1-1 leads to 1-2",
      "%s level %d" % (r["mode"], r["level"] + 1))

r = run(1500, "%s;40-1500:%d;%s" % (START_GAME, RIGHT, jumps(60, 1500)), col=170, level=1)
check(r["mode"] == "WIN", "flag pole of 1-2: the end", r["mode"])

# graphics pack from the SD card gives the same picture
run(60, "%s;40-60:%d" % (START_GAME, RIGHT), shots="50")
a = open(os.path.join(work, "shot_0050.ppm"), "rb").read()
run(60, "%s;40-60:%d" % (START_GAME, RIGHT), shots="50", use_pack=True)
b = open(os.path.join(work, "shot_0050.ppm"), "rb").read()
check(a == b and len(a) > 1000, "SD graphics pack loads the same graphics")

if failures:
    print("FAIL: game: %d checks failed" % len(failures))
    sys.exit(1)
print("PASS: game (NandTier Hopper rules on the PC build)")
