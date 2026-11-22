#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""The cartridge pack (sw/mkcarts.py) and the launcher's loader
(fw/fw-flash/loader.c, built for the PC as loader_host).

    test_carts.py <loader_host> <work dir>
"""

import os
import random
import re
import subprocess
import sys
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "sw"))
import mkcarts      # noqa: E402

host, work = sys.argv[1:3]
os.makedirs(work, exist_ok=True)
failures = []
SLOT = 0x100000


def check(ok, what):
    print("  %s: %s" % ("ok" if ok else "FAILED", what))
    if not ok:
        failures.append(what)


def run(image, flash, *cmd, env=None):
    out = subprocess.run([host, image, flash] + list(cmd), capture_output=True, text=True,
                         check=True, env=dict(os.environ, **(env or {}))).stdout
    return out


rng = random.Random(1)
games = [("FIRST GAME", bytes(rng.randrange(256) for _ in range(5000))),
         ("SECOND", bytes(rng.randrange(256) for _ in range(12345))),
         ("THIRD WITH FFS", b"\xff" * 700 + bytes(rng.randrange(256) for _ in range(3000)) + b"\xff" * 600),
         ("EXACT BLOCKS", bytes(rng.randrange(256) for _ in range(4096)))]
pack = mkcarts.make_pack(games)
image = os.path.join(work, "carts_test.img")
flash = os.path.join(work, "flash_test.bin")
with open(image, "wb") as f:
    f.write(pack)
if os.path.exists(flash):
    os.remove(flash)

# mkcarts round trip
listed = mkcarts.read_pack(pack)
check([(n, s, ok) for n, _, s, _, _, ok in listed] == [(n, len(d), True) for n, d in games],
      "mkcarts: directory lists every game with the right size and CRC")

out = run(image, flash, "list")
check("dir 4" in out and "cart 2 SECOND size=12345" in out, "loader reads the directory")
check(out.count("installed=0") == 4, "nothing is installed in an erased flash")


def flash_slot(n):
    return open(flash, "rb").read()[SLOT:SLOT + n]


for i, (name, data) in enumerate(games):
    out = run(image, flash, "install", str(i + 1))
    m = re.search(r"result=(-?\d+) erases=(\d+) programs=(\d+) errors=(\d+)", out)
    r, erases, programs, errors = map(int, m.groups())
    blocks = (len(data) + 511) // 512
    check(r == 0 and errors == 0 and flash_slot(len(data)) == data and erases == (len(data) + 4095) // 4096
          and programs <= 2 * blocks, "install %s (%d bytes): %d erases, %d page programs"
          % (name, len(data), erases, programs))

out = run(image, flash, "install", "4")
check("result=1 erases=0 programs=0" in out, "a game already in the flash is not copied again")
out = run(image, flash, "list")
check("cart 4 EXACT BLOCKS size=4096 crc=%08x installed=1" % zlib.crc32(games[3][1]) in out,
      "loader's CRC-32 matches zlib.crc32")

# blank pages are skipped (THIRD starts and ends with FF)
out = run(image, flash, "install", "3")
m = re.search(r"programs=(\d+)", out)
check(int(m.group(1)) < 2 * ((len(games[2][1]) + 511) // 512), "pages that are all FF are not programmed")

# a damaged directory, no card
bad = bytearray(pack)
bad[16 + 5] ^= 1
open(image + ".bad", "wb").write(bad)
check("dir -2" in run(image + ".bad", flash, "list"), "a damaged directory is no pack (-2)")
check("dir -1" in run(os.path.join(work, "no_such_card.img"), flash, "list"), "no card (-1)")
open(image + ".zero", "wb").write(bytes(1024))
check("dir -2" in run(image + ".zero", flash, "list"), "an empty card is no pack (-2)")

# a board with the bitstream in the same flash: firmware at 0x200000, the
# slot 1 MiB above it; the loader finds the offset from the launcher's bytes
launcher = os.path.join(work, "launcher_test.bin")
with open(launcher, "wb") as f:
    f.write(bytes(rng.randrange(256) for _ in range(4096)))
off_flash = os.path.join(work, "flash_offset_test.bin")
if os.path.exists(off_flash):
    os.remove(off_flash)
env = {"LOADER_XIP_OFFSET": "0x200000", "LOADER_LAUNCHER": launcher}
out = run(image, off_flash, "install", "2", env=env)
data = games[1][1]
fl = open(off_flash, "rb").read()
check("base 0x200000" in out and "result=0" in out and "errors=0" in out
      and fl[0x300000:0x300000 + len(data)] == data and fl[SLOT:SLOT + 16] == b"\xff" * 16,
      "flash offset 0x200000: found, game copied to 0x300000, nothing written at 0x100000")
out = run(image, off_flash, "install", "2", env=env)
check("result=1" in out, "flash offset 0x200000: the game is found there again (CRC through XIP)")
check("base 0x000000" in run(image, flash, "list"), "no offset: the launcher's bytes at 0 (Tang Nano 9K)")

# the real games
carts = os.path.join(HERE, "..", "..", "fw", "games", "build", "carts.img")
if os.path.exists(carts):
    out = run(carts, flash, "install", *[str(i) for i in range(1, 9)])
    check(out.count("result=0") == 8 and "errors=0" in out, "every real game installs (fw/games/build/carts.img)")

if failures:
    print("FAIL: carts: %d checks failed" % len(failures))
    sys.exit(1)
print("PASS: carts (cartridge pack and loader)")
