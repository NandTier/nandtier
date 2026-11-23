---
slug: risc-v-cpu
title: An RV32IM RISC-V CPU core in Verilog
nav: CPU
description: The NandTier CPU is a multi-cycle RV32IM RISC-V core written from scratch in readable Verilog, with hardware multiply and divide, cycle counters and traps. Stages, timing and supported instructions.
---
# The RV32IM CPU core

**`nandtier_core` is a multi-cycle RV32IM RISC-V core, written from scratch in Verilog to be read.** Each instruction passes through separate stage modules in `hw/core/`, one at a time, so you can follow a single instruction from fetch to write-back in a waveform.

## Stages

| Stage | Module | Work |
|---|---|---|
| FETCH | `nt_fetch` | program counter and instruction register |
| DECODE | `nt_decode` | decode, register file read (`nt_regfile`) |
| EXECUTE | `nt_execute` | ALU (`nt_alu`), branch compare (`nt_branch`), address and target adder, multiply and divide (`nt_muldiv`) |
| MEM | `nt_lsu` | load and store alignment, and the bus access |
| WB | | register write |

`nt_control` is the state machine (BOOT → FETCH → DECODE → EXECUTE → MEM → WB → FETCH, or TRAP), `nt_bus` drives the memory port, and `nt_csr` holds the read-only `cycle`, `time` and `instret` counters.

## Timing

- **4 cycles** per instruction, **7** for loads and stores, when memory answers one cycle after the request. Slower memory adds wait cycles.
- **Multiply:** 5 cycles. One 33 x 33 product in the FPGA's DSP block covers MUL, MULH, MULHSU and MULHU.
- **Divide:** 38 cycles, one bit per cycle.
- **Reset vector:** `0x8000_0000`, the boot ROM.

## Supported

- **RV32I**, the full base integer set.
- **M extension:** MUL, MULH, MULHSU, MULHU, DIV, DIVU, REM, REMU, with the specification's results for division by zero and overflow.
- **FENCE / FENCE.I** as no-ops, and counter reads (`rdcycle`, `rdtime`, `rdinstret` and their high halves).

**Not supported:** interrupts, the C (compressed) extension and machine-mode trap handlers. Illegal instructions, ECALL/EBREAK and misaligned accesses raise `trap` and halt the core until reset; the on-chip logic analyzer records it.

## How it is tested

`make -C test` checks the core module by module, runs ISA, C and 16 trap programs, varies bus latency from 0 to 4 cycles and at random, and runs random programs whose every bus write is compared with a Python instruction-set simulator (`test/core/rv32i_iss.py`).
