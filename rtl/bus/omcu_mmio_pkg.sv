`default_nettype none

// This file is deliberately a macro library rather than a SystemVerilog
// package.  It is compiled first by rtl/files.f and every board project, so
// the same expressions work in simulation, Gowin EDA and Yosys's conservative
// SystemVerilog frontend without a vendor-specific package-import switch.
`ifndef OMCU_MMIO_PKG_SV
`define OMCU_MMIO_PKG_SV

// Expands one byte-enable bit into the corresponding byte mask.
`define OMCU_WRITE_STROBE_MASK(strobe) { \
  {8{strobe[3]}}, {8{strobe[2]}}, {8{strobe[1]}}, {8{strobe[0]}} \
}

// Merges a 32-bit write into a register without changing disabled bytes.
`define OMCU_MERGE_WRITE(old_value, write_value, write_strobe) \
  (((old_value) & ~`OMCU_WRITE_STROBE_MASK(write_strobe)) | \
   ((write_value) &  `OMCU_WRITE_STROBE_MASK(write_strobe)))

`endif

`default_nettype wire
