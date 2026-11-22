#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""The ngame cartridges (fw/games/*), played on the PC build (ng_host).

    test_games.py <directory with the host builds>

Each game is played by its own demo player (the title screen starts one
after 600 frames) and with scripted controls, and its rules are checked
from the state it reports. Screenshots of the title and of a game go to
<directory>/shots/<game>_<frame>.ppm.
"""

import os
import re
import subprocess
import sys

RIGHT, LEFT, DOWN, UP, START, B, A, QUIT = 1, 2, 4, 8, 16, 32, 64, 256
DEMO = 600              # the demo starts after this many frames on the title

d = sys.argv[1]
shots = os.path.join(d, "shots")
os.makedirs(shots, exist_ok=True)
failures = []


def run(game, frames, script="", shot=""):
    out = subprocess.run([os.path.join(d, game), str(frames), os.path.join(shots, game), shot, script],
                         capture_output=True, text=True, check=True, timeout=120).stdout
    r = dict((k, int(v)) for k, v in re.findall(r"(\w+)=(-?\d+)", out))
    r["quit"] = "quit at frame" in out
    return r


def check(ok, game, what, r):
    print("  %s: %-9s %s   %s" % ("ok" if ok else "FAILED", game, what,
          " ".join("%s=%s" % kv for kv in r.items() if kv[0] != "quit")))
    if not ok:
        failures.append(game + ": " + what)


def script(*parts):
    return ";".join("%d-%d:%d" % p for p in parts)


START_GAME = (30, 31, START)

# every game: leaves when Q is pressed
for game in "snake bricks invaders pong blocks flappy racer".split():
    r = run(game, 200, script((50, 50, QUIT)), shot="20")
    check(r["quit"] and r["mode"] == 0, game, "title screen, Q leaves the game", r)

# snake
r = run("snake", DEMO + 1500, shot="%d" % (DEMO + 900))
check(r["demo"] == 1 and r["score"] >= 50 and r["len"] > 8, "snake", "demo player eats apples", r)
r = run("snake", 400, script(START_GAME, (60, 400, RIGHT)))
check(r["mode"] >= 2 and r["score"] == 0, "snake", "driving into the wall ends the game", r)
r = run("snake", 300, script(START_GAME, (60, 61, UP), (120, 121, LEFT), (160, 161, DOWN), (200, 201, RIGHT)))
check(r["mode"] == 1, "snake", "steering around keeps the snake alive", r)

# brick breaker
r = run("bricks", DEMO + 3000, shot="%d" % (DEMO + 1200))
check(r["demo"] == 1 and r["score"] > 300 and r["left"] < 80, "bricks", "demo player clears bricks", r)
r = run("bricks", 2500, script(START_GAME, (60, 61, A), (62, 2500, LEFT)))
check(r["lives"] < 3, "bricks", "missing the ball costs a life", r)

# alien raid
r = run("invaders", DEMO + 2500, shot="%d" % (DEMO + 600))
check(r["demo"] == 1 and r["score"] >= 100 and r["aliens"] < 40, "invaders", "demo player shoots aliens", r)
r = run("invaders", 3000, script(START_GAME, (40, 3000, LEFT)))
check(r["lives"] < 3 or r["mode"] >= 3, "invaders", "standing still gets the ship hit", r)

# pong
r = run("pong", 2500, script(START_GAME, (40, 2500, UP)))
check(r["cpu"] == 7 or r["losses"] == 1, "pong", "a paddle that does not move loses 0:7", r)
r = run("pong", DEMO + 1500, shot="%d" % (DEMO + 300))
check(r["demo"] == 1 and r["hits"] + r["you"] + r["cpu"] > 0, "pong", "demo rally", r)

# block drop
r = run("blocks", DEMO + 3000, shot="%d" % (DEMO + 1500))
check(r["demo"] == 1 and r["lines"] >= 10, "blocks", "demo player clears lines", r)
r = run("blocks", 1500, script(START_GAME, *[(f, f, UP) for f in range(60, 1500, 20)]))
check((r["mode"] >= 3 or r["best"] > 0) and r["score"] > 0, "blocks", "dropping without aiming tops out", r)

# flappy chip
r = run("flappy", DEMO + 700, shot="%d" % (DEMO + 400))
check(r["demo"] == 1 and r["score"] >= 2, "flappy", "demo bird flies through pipes", r)
r = run("flappy", 400, script(START_GAME, (60, 61, A)))
check(r["mode"] >= 3 and r["score"] == 0, "flappy", "without flapping the bird falls", r)

# road rush
r = run("racer", DEMO + 1500, shot="%d" % (DEMO + 600))
check(r["demo"] == 1 and r["overtaken"] > 3 and r["distance"] > 3000, "racer", "demo driver overtakes", r)
r = run("racer", 2000, script(START_GAME, (40, 2000, UP)))
check(r["lives"] < 3 and r["distance"] > 1000, "racer", "full speed in one lane ends in a crash", r)

if failures:
    print("FAIL: games: %d checks failed" % len(failures))
    sys.exit(1)
print("PASS: games (all ngame cartridges on the PC build)")
