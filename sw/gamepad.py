#!/usr/bin/env python3
# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
"""Use the PC keyboard as a game controller for the NandTier board.

    gamepad.py <serial port> [--game <n>] [--no-launch]

Opens the game menu from the firmware menu (sends "P"; with --game, also
the game's number, which starts it), then sends the controller state as
one byte, 0x80 | buttons, whenever it changes and 30 times a second.
Board messages are shown in the terminal. In the game menu, up / down
choose a game and Enter starts it; Q in a game goes back to the menu.

  move    arrows or A / D (W / S up / down)
  A       Space, K or X   (jump, fire, flap, turn, accelerate)
  B       J, Z or Shift   (run, turn back, brake)
  start   Enter
  1-9, 0  start that game from the game menu (0: game 10)
  quit    Esc (sends "q" to the game, then exits)

Key releases are only visible to programs that read the keyboard device
(/dev/input), which needs the "input" group:
    sudo usermod -aG input $USER      (then log out and in again)
Without it this falls back to the terminal: each key press holds the
button for a quarter of a second, and the keyboard's auto-repeat keeps it
held, so controls are a little less precise.
"""

import os
import select
import struct
import sys
import termios
import time
import tty

RIGHT, LEFT, DOWN, UP, START, RUN, JUMP = (1 << i for i in range(7))

# Linux key codes (input-event-codes.h)
EVDEV_KEYS = {
    106: RIGHT, 32: RIGHT,          # Right, D
    105: LEFT, 30: LEFT,            # Left, A
    108: DOWN, 31: DOWN,            # Down, S
    103: UP, 17: UP,                # Up, W
    28: START,                      # Enter
    57: JUMP, 37: JUMP, 45: JUMP,   # Space, K, X
    36: RUN, 44: RUN, 42: RUN, 54: RUN,     # J, Z, Shift
}
KEY_ESC = 1

DIGIT_KEYS = {2 + i: str(1 + i) for i in range(9)}   # evdev codes of 1-9

TERMINAL_KEYS = {
    "d": RIGHT, "a": LEFT, "s": DOWN, "w": UP, "\r": START, "\n": START,
    " ": JUMP, "k": JUMP, "x": JUMP, "j": RUN, "z": RUN,
    "\x1b[C": RIGHT, "\x1b[D": LEFT, "\x1b[B": DOWN, "\x1b[A": UP,
}


def find_keyboard():
    """/dev/input/eventN of a readable keyboard, or None."""
    try:
        text = open("/proc/bus/input/devices").read()
    except OSError:
        return None
    for block in text.split("\n\n"):
        if "EV=120013" not in block:            # keys + LEDs: a real keyboard
            continue
        for line in block.splitlines():
            if line.startswith("H: Handlers="):
                for h in line.split("=", 1)[1].split():
                    if h.startswith("event"):
                        path = "/dev/input/" + h
                        if os.access(path, os.R_OK):
                            return path
    return None


class EvdevKeys:
    """Real key down / up events."""
    EVENT = struct.Struct("llHHi")

    def __init__(self, path):
        self.fd = os.open(path, os.O_RDONLY | os.O_NONBLOCK)
        self.down = set()
        self.quit = False
        self.typed = ""

    def poll(self):
        try:
            data = os.read(self.fd, self.EVENT.size * 64)
        except BlockingIOError:
            data = b""
        for i in range(0, len(data) - self.EVENT.size + 1, self.EVENT.size):
            _, _, etype, code, value = self.EVENT.unpack_from(data, i)
            if etype != 1:                      # EV_KEY
                continue
            if code == KEY_ESC and value == 1:
                self.quit = True
            if code in DIGIT_KEYS and value == 1:
                self.typed += DIGIT_KEYS[code]
            if value == 1:
                self.down.add(code)
            elif value == 0:
                self.down.discard(code)
        b = 0
        for code in self.down:
            b |= EVDEV_KEYS.get(code, 0)
        return b


class TerminalKeys:
    """Key presses from the terminal, each holding its button briefly."""
    HOLD = 0.25

    def __init__(self):
        self.until = {}
        self.quit = False
        self.buf = ""
        self.typed = ""

    def poll(self):
        now = time.monotonic()
        while select.select([sys.stdin], [], [], 0)[0]:
            self.buf += os.read(sys.stdin.fileno(), 64).decode(errors="ignore")
        while self.buf:
            for seq in ("\x1b[A", "\x1b[B", "\x1b[C", "\x1b[D"):
                if self.buf.startswith(seq):
                    self.until[TERMINAL_KEYS[seq]] = now + self.HOLD
                    self.buf = self.buf[3:]
                    break
            else:
                ch, self.buf = self.buf[0], self.buf[1:]
                if ch == "\x1b" and not self.buf:
                    self.quit = True
                elif ch.lower() in TERMINAL_KEYS:
                    self.until[TERMINAL_KEYS[ch.lower()]] = now + self.HOLD
                elif "1" <= ch <= "9":
                    self.typed += ch
        b = 0
        for button, t in self.until.items():
            if t > now:
                b |= button
        return b


def main(argv):
    if len(argv) < 2 or "-h" in argv:
        print(__doc__)
        return 1
    import serial

    game = None
    if "--game" in argv:
        i = argv.index("--game")
        game = argv[i + 1]
        del argv[i:i + 2]

    path = find_keyboard()
    keys = EvdevKeys(path) if path else TerminalKeys()
    print("Keyboard: %s" % ("%s (key up/down)" % path if path else
          "terminal (no access to /dev/input; see gamepad.py -h)"))
    print("Esc quits.\r")

    old_tty = termios.tcgetattr(sys.stdin)
    tty.setraw(sys.stdin.fileno())
    try:
        with serial.Serial(argv[1], 115200, timeout=0) as port:
            if "--no-launch" not in argv:
                port.write(b"P")
                if game:
                    time.sleep(1.0)         # the menu reads the SD card first
                    port.write(b"0" if game == "10" else game.encode()[:1])
            last, last_sent = None, 0.0
            while not keys.quit:
                b = keys.poll()
                if keys.typed:
                    port.write(keys.typed.encode())
                    keys.typed = ""
                now = time.monotonic()
                if b != last or now - last_sent > 1 / 30:
                    port.write(bytes([0x80 | b]))
                    last, last_sent = b, now
                text = port.read(256)
                if text:
                    sys.stdout.write(text.decode(errors="replace").replace("\n", "\r\n"))
                    sys.stdout.flush()
                time.sleep(0.004)
            port.write(bytes([0x80]) + b"q")
            time.sleep(0.3)
            sys.stdout.write(port.read(1024).decode(errors="replace").replace("\n", "\r\n"))
    finally:
        termios.tcsetattr(sys.stdin, termios.TCSADRAIN, old_tty)
    print()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
