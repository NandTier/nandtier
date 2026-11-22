#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Compare a PPU frame captured from the RTL (tb_soc.v: P3, 4 bits per
colour) with one from the PC model (test/host: P6, 8 bits per colour).

    compare_ppm.py <rtl.ppm> <host.ppm>
"""

import sys


def read(path):
    data = open(path, "rb").read()
    if data.startswith(b"P3"):
        v = data.split()
        w, h, mx = int(v[1]), int(v[2]), int(v[3])
        nums = [int(x) * 255 // mx for x in v[4:4 + 3 * w * h]]
    else:
        head = data.split(b"\n", 3)
        w, h = map(int, head[1].split())
        nums = list(head[3][:3 * w * h])
    return w, h, [tuple(nums[i:i + 3]) for i in range(0, len(nums), 3)]


w1, h1, a = read(sys.argv[1])
w2, h2, b = read(sys.argv[2])
diff = sum(1 for x, y in zip(a, b) if x != y) if (w1, h1) == (w2, h2) else w1 * h1
if diff:
    print("FAIL: %s and %s differ in %d pixels" % (sys.argv[1], sys.argv[2], diff))
    sys.exit(1)
print("PASS: %s matches %s (%d pixels)" % (sys.argv[1], sys.argv[2], len(a)))
