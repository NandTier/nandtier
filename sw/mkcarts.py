#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Pack game cartridges into one SD card image for the NandTier launcher.

    mkcarts.py <out.img> "<NAME>=<cartridge.bin>" ...   make a pack
    mkcarts.py --hex <out.hex> <pack.img>               bytes for $readmemh (simulation)
    mkcarts.py --list <pack.img>                        show what is in a pack

The cartridges are fw/games/*/build/<game>.bin, linked for the flash
cartridge slot. The pack goes to the SD card from block 8192
(NT_CART_SD_BLOCK in fw/include/nandtier.h): `make program` writes it
together with the firmware, or with a card reader

    sudo dd if=fw/games/build/carts.img of=/dev/sdX bs=512 seek=8192

(check /dev/sdX twice: dd overwrites whatever it is told to).

Layout, in 512-byte blocks from the start of the pack:
  block 0       directory: "NTCART1\\0", count, checksum, then 32-byte
                entries {name[16], first block, size, CRC-32, load address}
                (fw/fw-flash/loader.c reads it)
  block 1...    the images, each padded to a whole block
"""

import struct
import sys
import zlib

BLOCK = 512
MAGIC = b"NTCART1\0"
SLOT = 0x00100000
SLOT_SIZE = 0x00100000
MAX_CARTS = 15


def make_pack(carts):
    """carts: list of (name, image bytes). Returns the pack."""
    if not 1 <= len(carts) <= MAX_CARTS:
        raise SystemExit("mkcarts: 1 to %d cartridges, not %d" % (MAX_CARTS, len(carts)))
    entries = b""
    images = b""
    block = 1
    for name, data in carts:
        raw = name.upper().encode("ascii")
        if len(raw) > 16:
            raise SystemExit("mkcarts: name %r is longer than 16 characters" % name)
        if not data or len(data) > SLOT_SIZE:
            raise SystemExit("mkcarts: %s: %d bytes does not fit the 1 MiB slot" % (name, len(data)))
        entries += struct.pack("<16sIIII", raw, block, len(data), zlib.crc32(data), SLOT)
        padded = data + bytes(-len(data) % BLOCK)
        images += padded
        block += len(padded) // BLOCK
    entries += bytes(BLOCK - 16 - len(entries))
    checksum = sum(struct.unpack("<%dI" % (len(entries) // 4), entries)) & 0xFFFFFFFF
    return MAGIC + struct.pack("<II", len(carts), checksum) + entries + images


def read_pack(pack):
    if pack[:8] != MAGIC:
        raise SystemExit("mkcarts: not a cartridge pack")
    count, checksum = struct.unpack_from("<II", pack, 8)
    if sum(struct.unpack_from("<124I", pack, 16)) & 0xFFFFFFFF != checksum:
        raise SystemExit("mkcarts: directory checksum wrong")
    out = []
    for i in range(count):
        name, block, size, crc, load = struct.unpack_from("<16sIIII", pack, 16 + 32 * i)
        data = pack[block * BLOCK:block * BLOCK + size]
        out.append((name.rstrip(b"\0").decode(), block, size, crc, load, zlib.crc32(data) == crc))
    return out


def main(argv):
    if len(argv) >= 3 and argv[1] == "--list":
        for i, (name, block, size, crc, load, ok) in enumerate(read_pack(open(argv[2], "rb").read())):
            print("%2d  %-16s  block %5d  %7d bytes  crc %08x  at %08x  %s"
                  % (i + 1, name, block, size, crc, load, "ok" if ok else "BAD CRC"))
        return 0
    if len(argv) == 4 and argv[1] == "--hex":
        data = open(argv[3], "rb").read()
        with open(argv[2], "w") as f:
            for i in range(0, len(data), 16):
                f.write(" ".join("%02x" % b for b in data[i:i + 16]) + "\n")
        return 0
    if len(argv) < 3 or argv[1].startswith("-"):
        print(__doc__)
        return 1
    carts = []
    for arg in argv[2:]:
        name, _, path = arg.partition("=")
        carts.append((name, open(path, "rb").read()))
    pack = make_pack(carts)
    with open(argv[1], "wb") as f:
        f.write(pack)
    print("mkcarts: %d games, %d bytes (%d SD blocks) -> %s"
          % (len(carts), len(pack), len(pack) // BLOCK, argv[1]))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
