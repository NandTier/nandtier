# Contributing to NandTier

Thanks for helping. NandTier is a teaching project first: every change should keep the design easy to read, easy to build and easy to test.

## Before you start

- For a bug, open an issue with the exact commands and output.
- For anything bigger than a small fix (a new peripheral, a board port, a change to the address map or the boot ROM protocol), open an issue first, so we can agree on the approach before you spend time on it.
- Questions are welcome in [Discussions](https://github.com/NandTier/nandtier/discussions).

## Set up and check

```bash
setup/setup.sh       # tools into tools/, nothing system-wide
make                 # boot ROM, launcher, games
make test            # must pass before every pull request
make fpga            # if you changed anything in hw/ or boards/
```

`make test` runs in about a minute. The whole-SoC simulation (`make -C sim`) needs the Gowin IDE and is not required for a pull request, but say in the pull request if you ran it.

## Style

- **Verilog:** Verilog-2005 that Yosys, Icarus Verilog and the Gowin IDE all accept. Modules in `hw/` start with `nt_`. One module per file, the file named after it. Tabs for indentation. Comment *why*, not *what*.
- **C:** C99, freestanding (no libc). Hardware registers come from `fw/include/nandtier.h`, never from magic numbers.
- **Python:** standard library plus `pyserial` only.
- **Headers:** every new source file starts with the copyright line and `SPDX-License-Identifier: Apache-2.0`, like the existing files.
- **Tests:** a new module or peripheral comes with a testbench in `test/`, wired into `test/Makefile`. A bug fix comes with a test that failed before the fix.

## Pull requests

- Keep each pull request to one change. Small pull requests are reviewed faster.
- Write the commit message as one line saying what changed, then a blank line and why, if that is not obvious.
- Update the README when commands, the address map, resource numbers or behaviour change.
- CI builds the firmware, runs the tests and builds the bitstreams for every pull request. It has to be green before merging.

## Good places to start

- A new game in `fw/games/`: copy `pong/`, read "Writing a Game" in the README.
- A port to another Gowin or ECP5 board: add a directory under `boards/`.
- Sound: the design has no audio output yet (see Known Issues).
- More tests: any peripheral corner case that is not checked yet.

## License

By contributing, you agree that your contribution is licensed under the [Apache License 2.0](LICENSE), like the rest of NandTier.
