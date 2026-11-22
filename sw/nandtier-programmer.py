#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Program the NandTier SPI flash (and optionally the SD card) over the UART.

    nandtier-programmer.py [--carts <carts.img>] [--no-firmware] [--flash-offset <n>]
                           <firmware.v> <serial port> [sd_image [sd_start_block [sd_max_sectors]]]

<firmware.v> is `objcopy -O verilog` output of the user firmware
(fw/fw-flash/build/fw-flash.v). Run the script, then press the reset
button: the boot ROM listens for the programmer for half a second after
reset.

--carts writes a game cartridge pack (sw/mkcarts.py, fw/games/build/carts.img)
to the SD card at block 8192, where the launcher's game menu finds it;
--flash-offset puts the firmware at that flash address instead of 0: on
boards whose bitstream is in the same flash (FLASH_OFFSET in
boards/<board>/board.mk, e.g. 0x100000 on the Tang Nano 20K).
--no-firmware leaves the flash alone (only the SD card is written). The SD
card goes through the board at about 10 KiB/s; a card reader and dd are
faster for big packs (see sw/mkcarts.py).

sd_image is a raw binary file, or a Gowin 4-bit memory file (.hex: one
nibble per line, lines starting with # are skipped) whose pixels are
packed two per byte, high nibble first. It is written to raw SD blocks
starting at sd_start_block (default 2048).

The protocol is described in fw/fw-brom/isp.c.
"""

import sys
import time

FLASH_SIZE = 8 * 1024 * 1024
CART_SD_BLOCK = 8192            # NT_CART_SD_BLOCK in fw/include/nandtier.h
SECTOR = 4096
PAGE = 256
SD_BLOCK = 512


class IspError(Exception):
    pass


class Isp:
    """Boot ROM commands. `port` needs read(n), write(data), reset_input_buffer()
    and a short read timeout (pyserial's Serial works)."""

    def __init__(self, port):
        self.port = port

    def _byte(self, timeout=5.0):
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            data = self.port.read(1)
            if data:
                return data[0]
        raise IspError("no answer from the boot ROM")

    def _expect(self, value, timeout=5.0):
        got = self._byte(timeout)
        if got != value:
            raise IspError("expected 0x%02x from the boot ROM, got 0x%02x" % (value, got))

    def connect(self, seconds=10.0, progress=None):
        """Ping until the boot ROM answers (the user presses reset meanwhile)."""
        deadline = time.monotonic() + seconds
        while time.monotonic() < deadline:
            self.port.reset_input_buffer()
            self.port.write(bytes([0x55, 0x55]))
            time.sleep(0.1)
            data = self.port.read(1)
            if data and data[0] == 0x56:
                time.sleep(0.1)
                self.port.read(16)          # answer to the second ping
                return
            if progress:
                progress()
        raise IspError("boot ROM not found: check the serial port and press reset")

    def load_page_buffer(self, data):
        assert 1 <= len(data) <= PAGE
        self.port.write(bytes([0x10]))
        self._expect(0x11)
        self.port.write(bytes([len(data) - 1]) + bytes(data))
        return self._byte() == sum(data) & 0xFF

    def erase_sector(self, addr):
        self.port.write(bytes([0x30]))
        self._expect(0x31)
        self.port.write(addr.to_bytes(3, "big"))
        self._expect(0x32, timeout=10.0)

    def program_page(self, addr):
        self.port.write(bytes([0x40]))
        self._expect(0x41)
        self.port.write(addr.to_bytes(3, "big"))
        self._expect(0x42)

    def sd_init(self):
        """Returns (status, r7 bytes or None); status 0 means success."""
        self.port.write(bytes([0x60]))
        self._expect(0x61, timeout=15.0)
        status = self._byte(timeout=15.0)
        r7 = None
        if status == 0x30:
            r7 = (self._byte(), self._byte())
        return status, r7

    def sd_write_block(self, block, data):
        """Returns 0 (written), 1 (card error) or 2 (checksum error)."""
        assert len(data) == SD_BLOCK
        self.port.write(bytes([0x62]))
        self._expect(0x63)
        self.port.write(block.to_bytes(4, "big") + bytes(data) + bytes([sum(data) & 0xFF]))
        return self._byte(timeout=15.0)

    def restart(self):
        self.port.write(bytes([0xF0]))
        self._expect(0xF1)


def read_flash_image(path):
    """Bytes for flash addresses 0.. from an objcopy verilog file. Data at
    other addresses (e.g. SRAM) is ignored."""
    image = bytearray()
    addr = 0
    with open(path) as f:
        for line in f:
            line = line.strip()
            if not line:
                continue
            if line.startswith("@"):
                addr = int(line[1:], 16)
                continue
            for value in line.split():
                if addr < FLASH_SIZE:
                    if addr >= len(image):
                        image.extend(b"\xff" * (addr + 1 - len(image)))
                    image[addr] = int(value, 16)
                addr += 1
    if not image:
        raise SystemExit("%s: no data for the flash (address 0x0)" % path)
    return bytes(image)


def read_sd_image(path):
    if path.lower().endswith(".hex"):
        nibbles = []
        with open(path) as f:
            for line in f:
                line = line.strip()
                if not line or line[0] in "#@":
                    continue
                nibbles.extend(int(v, 16) & 0xF for v in line.split())
        if len(nibbles) % 2:
            nibbles.append(0)
        data = bytes(nibbles[i] << 4 | nibbles[i + 1] for i in range(0, len(nibbles), 2))
    else:
        with open(path, "rb") as f:
            data = f.read()
    return data + bytes(-len(data) % SD_BLOCK)


def program_flash(isp, image, log=print, offset=0):
    """Write image to the flash from address offset on (a multiple of 4 KiB)."""
    if offset % SECTOR:
        raise IspError("flash offset 0x%x is not on a 4 KiB sector" % offset)
    sectors = (len(image) + SECTOR - 1) // SECTOR
    for s in range(sectors):
        base = s * SECTOR
        log("Flashing sector %d / %d (0x%06x)" % (s + 1, sectors, offset + base))
        isp.erase_sector(offset + base)
        for addr in range(base, min(base + SECTOR, len(image)), PAGE):
            data = image[addr:addr + PAGE]
            for _ in range(3):
                if isp.load_page_buffer(data):
                    break
            else:
                raise IspError("page buffer checksum keeps failing at 0x%06x" % (offset + addr))
            isp.program_page(offset + addr)


def write_sd(isp, data, start_block, log=print):
    status, r7 = isp.sd_init()
    if status:
        msg = "SD card initialisation failed, status 0x%02x" % status
        if r7:
            msg += " (CMD8 echo %02x %02x)" % r7
        raise IspError(msg)
    blocks = len(data) // SD_BLOCK
    for n in range(blocks):
        block = data[n * SD_BLOCK:(n + 1) * SD_BLOCK]
        for _ in range(3):
            result = isp.sd_write_block(start_block + n, block)
            if result != 2:             # retry a garbled transfer
                break
        if result:
            raise IspError("SD block %d: %s" % (start_block + n,
                           "checksum error" if result == 2 else "write failed"))
        log("SD block %d written (%d / %d)" % (start_block + n, n + 1, blocks))


def progress_line(text):
    print("\r" + text + "   ", end="", flush=True)


def main(argv):
    argv = list(argv)
    carts = None
    if "--carts" in argv:
        i = argv.index("--carts")
        carts = argv[i + 1] if i + 1 < len(argv) else None
        del argv[i:i + 2]
        if carts is None:
            print(__doc__)
            return 1
    offset = 0
    if "--flash-offset" in argv:
        i = argv.index("--flash-offset")
        offset = int(argv[i + 1], 0)
        del argv[i:i + 2]
    no_firmware = "--no-firmware" in argv
    if no_firmware:
        argv.remove("--no-firmware")
    if not 3 <= len(argv) <= 6 or "-h" in argv:
        print(__doc__)
        return 1
    image = read_flash_image(argv[1])
    sd_data = read_sd_image(argv[3]) if len(argv) > 3 else None
    sd_start = int(argv[4], 0) if len(argv) > 4 else 2048
    if sd_data is not None and len(argv) > 5:
        sd_data = sd_data[:int(argv[5], 0) * SD_BLOCK]
    cart_data = None
    if carts:
        with open(carts, "rb") as f:
            cart_data = f.read()
        if cart_data[:8] != b"NTCART1\0":
            print("%s is not a cartridge pack (sw/mkcarts.py)" % carts)
            return 1
        cart_data += bytes(-len(cart_data) % SD_BLOCK)

    import serial
    with serial.Serial(argv[2], 115200, timeout=0.01) as port:
        isp = Isp(port)
        print("Firmware: %d bytes%s. Press the reset button now."
              % (len(image), ", games: %d bytes" % len(cart_data) if cart_data else ""), flush=True)
        isp.connect(progress=lambda: print(".", end="", flush=True))
        print("\nBoot ROM found.")
        try:
            if not no_firmware:
                program_flash(isp, image, log=progress_line, offset=offset)
                print()
            if sd_data is not None:
                write_sd(isp, sd_data, sd_start, log=progress_line)
                print()
            if cart_data is not None:
                print("Writing the games to the SD card (block %d)" % CART_SD_BLOCK)
                write_sd(isp, cart_data, CART_SD_BLOCK, log=progress_line)
                print()
        except IspError as e:
            print("\nFailed:", e)
            return 1
        isp.restart()
        print("Done, the firmware is starting.")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
