# Copyright 2026 Abdul Muheet Ghani
# SPDX-License-Identifier: Apache-2.0
#
# NandTier clocks, for nextpnr (oss/Makefile)

create_clock -name clk     -period 37.037 [get_ports {clk}]    ;# 27 MHz crystal
create_clock -name clk_5x  -period 8.008  [get_nets {clk_5x}]  ;# rPLL, 124.875 MHz (OSER10 FCLK only)
create_clock -name clk_sys -period 40.040 [get_nets {clk_sys}] ;# CLKDIV /5, 24.975 MHz: CPU, bus, video
