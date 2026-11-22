#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""sw/nandtier-programmer.py against a simulated boot ROM.

Checks that a firmware image (including data above 1 MiB, where 3-byte
addresses matter) ends up in the simulated flash exactly, that unused
flash stays erased, and that SD blocks are written where requested.
"""

import importlib.util
import os
import random
import sys
import tempfile

HERE = os.path.dirname(os.path.abspath(__file__))
spec = importlib.util.spec_from_file_location(
    "programmer", os.path.join(HERE, "..", "..", "sw", "nandtier-programmer.py"))
prog = importlib.util.module_from_spec(spec)
spec.loader.exec_module(prog)


class FakeBootRom:
    """The boot ROM side of the protocol in fw/fw-brom/isp.c."""

    def __init__(self):
        self.flash = bytearray(b"\xff" * (2 * 1024 * 1024))
        self.sd = {}
        self.inbuf = bytearray()
        self.outbuf = bytearray()
        self.page = b""
        self.errors = []
        self.acked = False      # the command byte at inbuf[0] has been answered

    # serial port interface
    def reset_input_buffer(self):
        self.outbuf.clear()

    def read(self, n):
        data = bytes(self.outbuf[:n])
        del self.outbuf[:n]
        return data

    def write(self, data):
        self.inbuf += data
        while self._step():
            pass

    # protocol
    def _need(self, n):
        return len(self.inbuf) >= n

    def _step(self):
        if not self.inbuf:
            return False
        cmd = self.inbuf[0]
        # the boot ROM answers the command byte before reading the rest
        ack = {0x10: 0x11, 0x30: 0x31, 0x40: 0x41, 0x62: 0x63}.get(cmd)
        if ack is not None and not self.acked:
            self.outbuf.append(ack)
            self.acked = True
        done = self._command(cmd)
        if done:
            self.acked = False
        return done

    def _command(self, cmd):
        if cmd == 0x55:
            self.outbuf.append(0x56)
            del self.inbuf[:1]
        elif cmd == 0x10:
            if not self._need(2) or not self._need(2 + self.inbuf[1] + 1):
                return False
            n = self.inbuf[1] + 1
            self.page = bytes(self.inbuf[2:2 + n])
            self.outbuf.append(sum(self.page) & 0xFF)
            del self.inbuf[:2 + n]
        elif cmd == 0x30:
            if not self._need(4):
                return False
            a = int.from_bytes(self.inbuf[1:4], "big")
            if a % 4096:
                self.errors.append("erase at unaligned 0x%06x" % a)
            self.flash[a & ~4095:(a & ~4095) + 4096] = b"\xff" * 4096
            self.outbuf.append(0x32)
            del self.inbuf[:4]
        elif cmd == 0x40:
            if not self._need(4):
                return False
            a = int.from_bytes(self.inbuf[1:4], "big")
            for i, b in enumerate(self.page):
                addr = (a & ~255) | ((a + i) & 255)      # wraps within the page, like a flash
                if self.flash[addr] != 0xFF:
                    self.errors.append("programming unerased byte 0x%06x" % addr)
                self.flash[addr] &= b
            self.outbuf.append(0x42)
            del self.inbuf[:4]
        elif cmd == 0x60:
            self.outbuf += bytes([0x61, 0x00])
            del self.inbuf[:1]
        elif cmd == 0x62:
            if not self._need(1 + 4 + 512 + 1):
                return False
            block = int.from_bytes(self.inbuf[1:5], "big")
            data = bytes(self.inbuf[5:517])
            ok = sum(data) & 0xFF == self.inbuf[517]
            if ok:
                self.sd[block] = data
            self.outbuf.append(0 if ok else 2)
            del self.inbuf[:518]
        elif cmd == 0xF0:
            self.outbuf.append(0xF1)
            del self.inbuf[:1]
        else:
            self.errors.append("unknown command 0x%02x" % cmd)
            del self.inbuf[:1]
        return True


def main():
    rnd = random.Random(1)
    failures = []

    # firmware: 10000 bytes at 0, 700 bytes at 0x150010, SRAM data ignored
    low = bytes(rnd.randrange(256) for _ in range(10000))
    high = bytes(rnd.randrange(256) for _ in range(700))
    with tempfile.NamedTemporaryFile("w", suffix=".v", delete=False) as f:
        for base, data in ((0, low), (0x150010, high), (0x40000000, b"\x12\x34")):
            f.write("@%08X\n" % base)
            for i in range(0, len(data), 16):
                f.write(" ".join("%02X" % b for b in data[i:i + 16]) + "\n")
        path = f.name
    image = prog.read_flash_image(path)
    os.unlink(path)

    rom = FakeBootRom()
    isp = prog.Isp(rom)
    isp.connect(seconds=1)
    prog.program_flash(isp, image, log=lambda *a: None)

    expected = bytearray(b"\xff" * len(rom.flash))
    expected[0:len(low)] = low
    expected[0x150010:0x150010 + len(high)] = high
    if rom.flash != expected:
        bad = next(i for i in range(len(expected)) if rom.flash[i] != expected[i])
        failures.append("flash differs first at 0x%06x" % bad)

    # the same firmware at flash offset 0x200000 (boards with the bitstream
    # in the flash): nothing below it is touched
    rom2 = FakeBootRom()
    isp2 = prog.Isp(rom2)
    isp2.connect(seconds=1)
    prog.program_flash(isp2, low, log=lambda *a: None, offset=0x200000)
    if rom2.flash[0x200000:0x200000 + len(low)] != low or rom2.flash[:0x200000] != b"\xff" * 0x200000:
        failures.append("firmware at flash offset 0x200000 wrong")
    failures += rom2.errors

    sd_data = bytes(rnd.randrange(256) for _ in range(3 * 512))
    prog.write_sd(isp, sd_data, 2048, log=lambda *a: None)
    for n in range(3):
        if rom.sd.get(2048 + n) != sd_data[n * 512:(n + 1) * 512]:
            failures.append("SD block %d wrong" % (2048 + n))
    isp.restart()

    failures += rom.errors
    if failures:
        for msg in failures:
            print("  " + msg)
        print("FAIL: nandtier-programmer")
        return 1
    print("PASS: nandtier-programmer (%d flash bytes, 3 SD blocks)" % len(image))
    return 0


if __name__ == "__main__":
    sys.exit(main())
