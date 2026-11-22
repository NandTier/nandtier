# NandTier ILA access over the ULX3S ECP5 user JTAG chain.
#
# Create the OpenOCD tap before sourcing this file, for example:
#   jtag newtap ecp5 tap -irlen 8
#
# OpenOCD must already be initialized. The adapter configuration is specific
# to the JTAG probe connected to the board.

set nt_ila_tap "ecp5.tap"
set nt_ila_ir 0x32
set nt_ila_seq 0

proc nt_ila_scan {frame} {
	global nt_ila_tap nt_ila_ir
	irscan $nt_ila_tap $nt_ila_ir
	set result [drscan $nt_ila_tap 64 $frame]
	return [expr {$result}]
}

proc nt_ila_xfer {op addr data} {
	global nt_ila_seq
	set nt_ila_seq [expr {($nt_ila_seq + 1) & 0xFF}]
	if {$nt_ila_seq == 0} {
		set nt_ila_seq 1
	}

	set frame [expr {(($op & 0xF) << 60) |
	                 (($addr & 0xFF) << 52) |
	                 (($nt_ila_seq & 0xFF) << 44) |
	                 ($data & 0xFFFFFFFF)}]
	nt_ila_scan $frame

	for {set attempt 0} {$attempt < 8} {incr attempt} {
		runtest 64
		set response [nt_ila_scan 0]
		set response_seq [expr {($response >> 52) & 0xFF}]
		if {$response_seq == $nt_ila_seq} {
			set status [expr {($response >> 60) & 0xF}]
			if {$status != 0} {
				error [format "JTAG request failed: status %x" $status]
			}
			return [expr {$response & 0xFFFFFFFF}]
		}
	}
	error "JTAG request timed out or was overwritten"
}

proc nt_ila_read {offset} {
	set value [nt_ila_xfer 2 $offset 0]
	puts [format "ILA[%02x] = %08x" $offset $value]
	return $value
}

proc nt_ila_write {offset value} {
	nt_ila_xfer 1 $offset $value
}

proc nt_ila_dump {} {
	set status [nt_ila_xfer 2 0x00 0]
	set count [expr {($status >> 8) & 0xFF}]
	puts [format "index address  data     flags"]
	for {set index 0} {$index < $count} {incr index} {
		nt_ila_write 0x10 $index
		set address [nt_ila_xfer 2 0x14 0]
		set data [nt_ila_xfer 2 0x18 0]
		set flags [nt_ila_xfer 2 0x1C 0]
		puts [format "%03d   %08x %08x %02x" $index $address $data $flags]
	}
}

proc nt_cpu_read {offset} {
	return [nt_ila_xfer 2 $offset 0]
}

proc nt_cpu_write {offset value} {
	nt_ila_xfer 1 $offset $value
}

proc nt_cpu_status {} {
	set status [nt_cpu_read 0x80]
	puts [format "CPU status: halted=%d trap=%d halt-request=%d" \
		[expr {$status & 1}] [expr {($status >> 1) & 1}] \
		[expr {($status >> 2) & 1}]]
	return $status
}

proc nt_cpu_wait_halted {} {
	for {set attempt 0} {$attempt < 256} {incr attempt} {
		set status [nt_cpu_read 0x80]
		if {$status & 1} {
			return $status
		}
	}
	error "CPU did not halt before timeout"
}

proc nt_cpu_halt {} {
	nt_cpu_write 0x80 1
	nt_cpu_wait_halted
}

proc nt_cpu_resume {} {
	nt_cpu_write 0x80 2
}

proc nt_cpu_step {} {
	nt_cpu_write 0x80 4
	nt_cpu_wait_halted
}

proc nt_cpu_pc {} {
	set pc [nt_cpu_read 0x84]
	puts [format "PC = %08x" $pc]
	return $pc
}

proc nt_cpu_set_pc {value} {
	nt_cpu_write 0x84 $value
}

proc nt_cpu_gpr_read {index} {
	if {$index < 0 || $index > 31} {
		error "GPR index must be in the range 0..31"
	}
	nt_cpu_write 0x88 $index
	set value [nt_cpu_read 0x8C]
	puts [format "x%d = %08x" $index $value]
	return $value
}

proc nt_cpu_gpr_write {index value} {
	if {$index < 0 || $index > 31} {
		error "GPR index must be in the range 0..31"
	}
	nt_cpu_write 0x88 $index
	nt_cpu_write 0x8C $value
}

proc nt_cpu_system_reset {asserted} {
	nt_cpu_write 0x90 [expr {$asserted ? 1 : 0}]
}
