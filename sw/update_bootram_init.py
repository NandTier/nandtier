#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Update Gowin boot-RAM INIT_RAM values from fw-brom .mi files."""

import argparse
import re
from pathlib import Path

BANK_COUNT = 4
BANK_BYTES = 2048
BYTES_PER_INIT = 32
INIT_COUNT = BANK_BYTES // BYTES_PER_INIT
INIT_RE = re.compile(
    r"^(\s*defparam\s+sp_inst_0\.INIT_RAM_([0-9A-Fa-f]+)\s*=\s*256'h)"
    r"([0-9A-Fa-f]+)(;.*)$"
)


def read_mi(path):
    values = []
    for line in path.read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#"):
            continue
        if not re.fullmatch(r"[0-9A-Fa-f]{2}", line):
            raise ValueError(f"{path}: invalid memory byte: {line!r}")
        values.append(int(line, 16))
    if len(values) != BANK_BYTES:
        raise ValueError(f"{path}: expected {BANK_BYTES} bytes, found {len(values)}")
    return values


def update_verilog(verilog_path, mi_path, dry_run=False):
    values = read_mi(mi_path)
    lines = verilog_path.read_text().splitlines(keepends=True)
    seen = set()
    output = []

    for line in lines:
        match = INIT_RE.match(line.rstrip("\r\n"))
        if not match:
            output.append(line)
            continue

        init_index = int(match.group(2), 16)
        if init_index >= INIT_COUNT:
            output.append(line)
            continue

        start = init_index * BYTES_PER_INIT
        chunk = values[start:start + BYTES_PER_INIT]
        literal = "".join(f"{value:02X}" for value in reversed(chunk))
        newline = "\r\n" if line.endswith("\r\n") else "\n"
        output.append(f"{match.group(1)}{literal}{match.group(4)}{newline}")
        seen.add(init_index)

    missing = set(range(INIT_COUNT)) - seen
    if missing:
        missing_text = ", ".join(f"{index:02X}" for index in sorted(missing))
        raise ValueError(f"{verilog_path}: missing INIT_RAM entries: {missing_text}")

    if not dry_run:
        verilog_path.write_text("".join(output))
    return len(seen)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument(
        "--mi-dir", type=Path,
        default=Path("fw/fw-brom/build"),
        help="directory containing fw-brom_0.mi through fw-brom_3.mi",
    )
    parser.add_argument(
        "--v-dir", type=Path,
        default=Path("project/src/gowin_sp"),
        help="directory containing bootram_2kx8_0.v through bootram_2kx8_3.v",
    )
    parser.add_argument(
        "--dry-run", action="store_true",
        help="validate inputs without modifying Verilog files",
    )
    parser.add_argument(
        "--backup", action="store_true",
        help="create a .bak copy before each Verilog file is changed",
    )
    args = parser.parse_args()

    for bank in range(BANK_COUNT):
        mi_path = args.mi_dir / f"fw-brom_{bank}.mi"
        verilog_path = args.v_dir / f"bootram_2kx8_{bank}.v"
        if not mi_path.is_file():
            raise SystemExit(f"missing MI file: {mi_path}")
        if not verilog_path.is_file():
            raise SystemExit(f"missing Verilog file: {verilog_path}")
        if args.backup and not args.dry_run:
            verilog_path.with_suffix(verilog_path.suffix + ".bak").write_bytes(
                verilog_path.read_bytes()
            )
        count = update_verilog(verilog_path, mi_path, args.dry_run)
        action = "would update" if args.dry_run else "updated"
        print(f"{action} {verilog_path}: {count} INIT_RAM entries")


if __name__ == "__main__":
    main()
