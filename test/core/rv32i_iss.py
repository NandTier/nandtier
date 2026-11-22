#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""RV32I instruction set simulator, used as the reference for the random
program tests.

    rv32i_iss.py <program.hex> <rtl_store_log>

Runs <program.hex> (objcopy -O verilog, loaded at 0x8000_0000, 64 KiB RAM)
from 0x8000_0000 until it writes TOHOST (0x1000_0000), recording every
store as "address strobes data" -- the bus view: word address, byte
strobes, data of the strobed bytes -- and compares that list with the one
tb_core.v wrote for the RTL (+storelog=<file>).

Only what the random programs use is supported: RV32I without FENCE,
ECALL/EBREAK and CSRs.
"""

import sys

RAM_BASE = 0x80000000
RAM_SIZE = 0x10000
TOHOST = 0x10000000
MAX_STEPS = 2_000_000


def sx(value, bits):
    value &= (1 << bits) - 1
    return value - (1 << bits) if value >> (bits - 1) else value


def load_hex(path):
    ram = bytearray(RAM_SIZE)
    addr = RAM_BASE
    with open(path) as f:
        for line in f:
            line = line.strip()
            if line.startswith("@"):
                addr = int(line[1:], 16)
            elif line:
                for b in line.split():
                    ram[addr - RAM_BASE] = int(b, 16)
                    addr += 1
    return ram


class Machine:
    def __init__(self, ram):
        self.ram = ram
        self.x = [0] * 32
        self.pc = RAM_BASE
        self.stores = []
        self.done = False

    def load(self, addr, size, signed):
        off = addr - RAM_BASE
        if not 0 <= off <= RAM_SIZE - size:
            raise RuntimeError("load from 0x%08x" % addr)
        v = int.from_bytes(self.ram[off:off + size], "little")
        return sx(v, size * 8) & 0xFFFFFFFF if signed else v

    def store(self, addr, size, value):
        if addr % size:
            raise RuntimeError("misaligned store to 0x%08x" % addr)
        value &= (1 << (size * 8)) - 1
        shift = (addr & 3) * 8
        strobes = ((1 << size) - 1) << (addr & 3)
        self.stores.append((addr & ~3, strobes, (value << shift) & 0xFFFFFFFF))
        if addr == TOHOST:
            self.done = True
            return
        off = addr - RAM_BASE
        if not 0 <= off <= RAM_SIZE - size:
            raise RuntimeError("store to 0x%08x" % addr)
        self.ram[off:off + size] = value.to_bytes(size, "little")

    def step(self):
        insn = self.load(self.pc, 4, False)
        op, rd, f3 = insn & 0x7F, (insn >> 7) & 31, (insn >> 12) & 7
        rs1, rs2, f7 = (insn >> 15) & 31, (insn >> 20) & 31, insn >> 25
        a, b = self.x[rs1], self.x[rs2]
        imm_i = sx(insn >> 20, 12)
        imm_s = sx((f7 << 5) | ((insn >> 7) & 31), 12)
        imm_b = sx(((insn >> 31) << 12) | (((insn >> 7) & 1) << 11) |
                   (((insn >> 25) & 63) << 5) | (((insn >> 8) & 15) << 1), 13)
        imm_j = sx(((insn >> 31) << 20) | (((insn >> 12) & 255) << 12) |
                   (((insn >> 20) & 1) << 11) | (((insn >> 21) & 1023) << 1), 21)
        next_pc = self.pc + 4
        result = None

        if op == 0x37:                                  # LUI
            result = insn & 0xFFFFF000
        elif op == 0x17:                                # AUIPC
            result = self.pc + (insn & 0xFFFFF000)
        elif op == 0x6F:                                # JAL
            result, next_pc = self.pc + 4, self.pc + imm_j
        elif op == 0x67:                                # JALR
            result, next_pc = self.pc + 4, (a + imm_i) & ~1
        elif op == 0x63:                                # branches
            sa, sb = sx(a, 32), sx(b, 32)
            taken = {0: a == b, 1: a != b, 4: sa < sb, 5: sa >= sb, 6: a < b, 7: a >= b}[f3]
            if taken:
                next_pc = self.pc + imm_b
        elif op == 0x03:                                # loads
            size, signed = {0: (1, True), 1: (2, True), 2: (4, False), 4: (1, False), 5: (2, False)}[f3]
            result = self.load((a + imm_i) & 0xFFFFFFFF, size, signed)
        elif op == 0x23:                                # stores
            self.store((a + imm_s) & 0xFFFFFFFF, {0: 1, 1: 2, 2: 4}[f3], b)
        elif op == 0x33 and f7 == 1:                    # M extension
            sa, sb = sx(a, 32), sx(b, 32)
            if f3 == 0:
                result = a * b
            elif f3 == 1:
                result = (sa * sb) >> 32
            elif f3 == 2:
                result = (sa * b) >> 32
            elif f3 == 3:
                result = (a * b) >> 32
            elif f3 == 4:                               # DIV: rounds towards zero
                result = -1 if b == 0 else (sa if (sa == -2**31 and sb == -1) else
                                            int(abs(sa) // abs(sb)) * (1 if (sa < 0) == (sb < 0) else -1))
            elif f3 == 5:
                result = 0xFFFFFFFF if b == 0 else a // b
            elif f3 == 6:                               # REM: sign of the dividend
                result = sa if b == 0 else (0 if (sa == -2**31 and sb == -1) else
                                            (abs(sa) % abs(sb)) * (1 if sa >= 0 else -1))
            else:
                result = a if b == 0 else a % b
        elif op in (0x13, 0x33):                        # ALU
            if op == 0x13:
                b = imm_i & 0xFFFFFFFF
                alt = f3 == 5 and (f7 & 0x20)
            else:
                alt = f7 & 0x20
            sh = b & 31
            result = {
                0: (a - b) if alt else (a + b),
                1: a << sh,
                2: int(sx(a, 32) < sx(b, 32)),
                3: int(a < b),
                4: a ^ b,
                5: (sx(a, 32) >> sh) if alt else (a >> sh),
                6: a | b,
                7: a & b,
            }[f3]
        else:
            raise RuntimeError("unsupported instruction %08x at %08x" % (insn, self.pc))

        if result is not None and rd:
            self.x[rd] = result & 0xFFFFFFFF
        self.pc = next_pc & 0xFFFFFFFF


def main():
    if len(sys.argv) != 3:
        sys.exit(__doc__)
    m = Machine(load_hex(sys.argv[1]))
    try:
        for _ in range(MAX_STEPS):
            m.step()
            if m.done:
                break
        else:
            raise RuntimeError("no TOHOST write after %d instructions" % MAX_STEPS)
    except RuntimeError as e:
        print("FAIL: reference model: %s" % e)
        return 1

    with open(sys.argv[2]) as f:
        rtl = [tuple(int(v, 16) for v in line.split()) for line in f if line.strip()]

    for n, (want, got) in enumerate(zip(m.stores, rtl)):
        if want != got:
            print("FAIL: write #%d differs" % n)
            print("  reference: addr=%08x strb=%x data=%08x" % want)
            print("  rtl:       addr=%08x strb=%x data=%08x" % got)
            return 1
    if len(m.stores) != len(rtl):
        print("FAIL: reference made %d writes, rtl %d" % (len(m.stores), len(rtl)))
        return 1
    print("PASS: %s (%d writes match the reference model)" % (sys.argv[1], len(rtl)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
