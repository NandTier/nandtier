#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Split a firmware image into the four byte lanes of a 32-bit RAM.

    mem_image.py <image.v> <base address> <size in bytes> <output prefix>

<image.v> is `objcopy -O verilog` output. Byte lane n holds bytes
n, n+4, n+8, ... of the memory starting at <base address>. Writes, for
n = 0..3:

    <prefix>_n.mi    Gowin memory init file (8-bit words), as read by
                     sw/update_bootram_init.py
    <prefix>_n.hex   one byte per line for $readmemh in simulation
"""

import sys


def read_verilog_hex(path, base, size):
    image = bytearray(size)
    addr = None
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith('@'):
                addr = int(line[1:], 16) - base
                continue
            for byte in line.split():
                if addr is None or not 0 <= addr < size:
                    raise SystemExit("%s: data outside 0x%08x..0x%08x"
                                     % (path, base, base + size - 1))
                image[addr] = int(byte, 16)
                addr += 1
    return image


def main():
    if len(sys.argv) != 5:
        sys.exit(__doc__)
    path, base, size, prefix = sys.argv[1], int(sys.argv[2], 0), int(sys.argv[3], 0), sys.argv[4]
    image = read_verilog_hex(path, base, size)
    depth = size // 4

    for lane in range(4):
        data = image[lane::4]
        with open("%s_%d.mi" % (prefix, lane), "w") as f:
            f.write("#File_format=Hex\n#Address_depth=%d\n#Data_width=8\n" % depth)
            f.writelines("%02X\n" % b for b in data)
        with open("%s_%d.hex" % (prefix, lane), "w") as f:
            f.writelines("%02X\n" % b for b in data)


if __name__ == "__main__":
    main()
