#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Turn a game's pixel art into C data for ngame (fw/sdk/ngame.h).

    mkart.py <art.py> <out.c> <out.h>

art.py defines, one character per pixel:

  KEY           16 characters: KEY[i] is colour i (KEY[0] is transparent)
  BG_PALETTES   up to 4 lists of 12-bit 0xRGB colours (background palettes)
  SPR_PALETTES  up to 4 lists (sprite palettes)
  TILES         {name: 8 rows of 8}      8 x 8 tiles, numbered from 0x40
  SPRITES       {name: 16 rows of 16}    16 x 16 sprites, numbered from 0x80
  BLOCKS        {name: 16 rows of 16}    16 x 16 background blocks, cut into
                8 x 8 tiles after TILES (identical or mirrored tiles
                shared); writes B_<NAME>, ART_BLOCKS, art_block_tiles[][4]
                (top left, top right, bottom left, bottom right: tile
                numbers with NG_TILE_HFLIP / NG_TILE_VFLIP) and
                art_block_pal[]
  BLOCK_PALETTE {name: n}                background palette of a block (0)
  FONT_BG       colour behind the letters (default 0, transparent); the
                space stays transparent, so text over a 3D picture can have
                a solid background where there is text
  BIG_FONT      True: add the 16 tiles T_QUAD0.. for ng_big_text() (big
                letters, 4 x 4 pixels per font pixel, in colour 15 with a
                colour 1 shadow line underneath)

Tiles 0x00-0x3F are the font (ASCII 0x20-0x5F) in colour 15, so colour 15
of a palette is its text colour. Writes T_<NAME> and S_<NAME> tile numbers,
ART_TILES (tiles to load) and the arrays art_chr, art_palette and art_font
(the font as 5-bit rows, for ng_big_text()).
"""

import importlib.util
import os
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, os.path.join(HERE, "..", "..", "hw", "video"))

import gen_font     # noqa: E402  (the terminal font)

FONT_COLOUR = 15


def tile_words(pix, x0, y0):
    """8 words for the 8 x 8 tile at (x0, y0): pixel k of a row in bits 4k+3..4k"""
    words = []
    for r in range(8):
        w = 0
        for k in range(8):
            w |= pix[y0 + r][x0 + k] << (4 * k)
        words.append(w)
    return words


def pixels(name, rows, key, size):
    if len(rows) != size:
        raise SystemExit("%s: %d rows, expected %d" % (name, len(rows), size))
    out = []
    for row in rows:
        if len(row) != size:
            raise SystemExit("%s: row %r is not %d wide" % (name, row, size))
        try:
            out.append([key.index(ch) for ch in row])
        except ValueError:
            raise SystemExit("%s: row %r has a character that is not in KEY" % (name, row))
    return out


def palettes(lists, what):
    if len(lists) > 4:
        raise SystemExit("more than 4 %s palettes" % what)
    out = []
    for p in lists:
        if len(p) > 16:
            raise SystemExit("a %s palette has more than 16 colours" % what)
        out += list(p) + [0xFFF] * (16 - len(p))    # unused: white (the text colour)
    return out + [0] * (64 - len(out))


def main():
    art_path, out_c, out_h = sys.argv[1:4]
    spec = importlib.util.spec_from_file_location("art", art_path)
    art = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(art)
    key = art.KEY
    if len(key) != 16:
        raise SystemExit("KEY must have 16 characters")

    chr_tiles = [[0] * 8 for _ in range(256)]
    font_bg = getattr(art, "FONT_BG", 0)
    for code in range(0x20, 0x60):
        rows = gen_font.GLYPHS[chr(code)]
        bg = font_bg if code != 0x20 else 0
        pix = [[bg] * 8 for _ in range(8)]
        for r in range(8):
            for c in range(5):
                if rows[r][c] == "#":
                    pix[r][c + 1] = FONT_COLOUR
        chr_tiles[code - 0x20] = tile_words(pix, 0, 0)

    names = []
    used = 0x40
    tiles = dict(getattr(art, "TILES", {}))
    if getattr(art, "BIG_FONT", False):
        for q in range(16):
            rows = []
            for y in range(8):
                row = ""
                for x in range(8):
                    on = q >> ((y >= 4) * 2 + (x >= 4)) & 1
                    # shadow under a filled quarter whose lower neighbour is empty
                    below = y == 3 and not (q >> (2 + (x >= 4)) & 1)
                    row += (key[1] if below else key[15]) if on else key[0]
                rows.append(row)
            tiles["quad%d" % q] = rows
    if len(tiles) > 64:
        raise SystemExit("more than 64 tiles")
    for i, (name, rows) in enumerate(tiles.items()):
        chr_tiles[0x40 + i] = tile_words(pixels(name, rows, key, 8), 0, 0)
        names.append(("T_" + name.upper(), 0x40 + i))
        used = max(used, 0x41 + i)

    blocks = getattr(art, "BLOCKS", {})
    block_pal = getattr(art, "BLOCK_PALETTE", {})
    block_tiles = []
    seen = {}
    next_tile = 0x40 + len(tiles)
    for name, rows in blocks.items():
        pix = pixels(name, rows, key, 16)
        ids = []
        for y0, x0 in ((0, 0), (0, 8), (8, 0), (8, 8)):
            words = tuple(tile_words(pix, x0, y0))
            # the same tile mirrored: tile map flip bits instead of a new tile
            hflip = tuple(sum(((w >> (4 * k)) & 15) << (4 * (7 - k)) for k in range(8)) for w in words)
            variants = ((words, 0), (hflip, 0x400), (words[::-1], 0x800), (hflip[::-1], 0xC00))
            for v, flags in variants:
                if v in seen:
                    ids.append(seen[v] | flags)
                    break
            else:
                if next_tile >= 0x80:
                    raise SystemExit("too many 8 x 8 tiles: TILES and BLOCKS share 0x40-0x7F")
                seen[words] = next_tile
                chr_tiles[next_tile] = list(words)
                ids.append(next_tile)
                next_tile += 1
        block_tiles.append((name, ids, block_pal.get(name, 0)))
        used = max(used, next_tile)

    sprites = getattr(art, "SPRITES", {})
    if len(sprites) > 32:
        raise SystemExit("more than 32 sprites")
    for i, (name, rows) in enumerate(sprites.items()):
        base = (8 + 2 * (i // 8)) * 16 + 2 * (i % 8)
        pix = pixels(name, rows, key, 16)
        chr_tiles[base] = tile_words(pix, 0, 0)
        chr_tiles[base + 1] = tile_words(pix, 8, 0)
        chr_tiles[base + 16] = tile_words(pix, 0, 8)
        chr_tiles[base + 17] = tile_words(pix, 8, 8)
        names.append(("S_" + name.upper(), base))
        used = max(used, base + 18)

    palette = palettes(art.BG_PALETTES, "background") + palettes(art.SPR_PALETTES, "sprite")
    font = []
    for code in range(0x20, 0x60):
        font.append([sum(1 << (4 - c) for c in range(5) if gen_font.GLYPHS[chr(code)][r][c] == "#")
                     for r in range(8)])
    words = [w for t in chr_tiles[:used] for w in t]
    src = os.path.relpath(art_path, os.path.dirname(os.path.abspath(out_c)))

    with open(out_h, "w") as h:
        h.write("// Generated by fw/sdk/mkart.py from %s -- do not edit.\n" % src)
        h.write("// SPDX-License-Identifier: Apache-2.0\n\n")
        h.write("#ifndef ART_H\n#define ART_H\n\n#include <stdint.h>\n\n")
        for n, v in names:
            h.write("#define %-20s 0x%02X\n" % (n, v))
        for i, (name, ids, pal) in enumerate(block_tiles):
            h.write("#define %-20s %d\n" % ("B_" + name.upper(), i))
        if block_tiles:
            h.write("#define ART_BLOCKS %d\n" % len(block_tiles))
            h.write("extern const uint16_t art_block_tiles[ART_BLOCKS][4];\n")
            h.write("extern const uint8_t art_block_pal[ART_BLOCKS];\n")
        h.write("\n#define ART_TILES %d\n\n" % used)
        h.write("extern const uint32_t art_chr[ART_TILES * 8];\n")
        h.write("extern const uint16_t art_palette[128];\n")
        h.write("extern const uint8_t  art_font[64][8];   // ASCII 0x20-0x5F, bit 4 = left\n\n#endif\n")

    with open(out_c, "w") as c:
        c.write("// Generated by fw/sdk/mkart.py from %s -- do not edit.\n" % src)
        c.write("// SPDX-License-Identifier: Apache-2.0\n\n#include \"art.h\"\n\n")
        c.write("const uint32_t art_chr[ART_TILES * 8] = {\n")
        for i in range(0, len(words), 8):
            c.write("\t" + ", ".join("0x%08x" % w for w in words[i:i + 8]) + ",\n")
        c.write("};\n\nconst uint16_t art_palette[128] = {\n")
        for i in range(0, 128, 16):
            c.write("\t" + ", ".join("0x%03x" % p for p in palette[i:i + 16]) + ",\n")
        c.write("};\n")
        if block_tiles:
            c.write("\nconst uint16_t art_block_tiles[ART_BLOCKS][4] = {\n")
            for name, ids, pal in block_tiles:
                c.write("\t{0x%03x, 0x%03x, 0x%03x, 0x%03x},  // %s\n" % (*ids, name))
            c.write("};\n\nconst uint8_t art_block_pal[ART_BLOCKS] = {")
            c.write(", ".join(str(pal) for _, _, pal in block_tiles) + "};\n")
        c.write("\nconst uint8_t art_font[64][8] = {\n")
        for i, rows in enumerate(font):
            c.write("\t{%s},  // %r\n" % (", ".join("0x%02x" % r for r in rows), chr(0x20 + i)))
        c.write("};\n")


if __name__ == "__main__":
    main()
