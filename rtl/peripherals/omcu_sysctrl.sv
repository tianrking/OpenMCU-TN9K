`default_nettype none

// Read-only hardware identity and capability metadata. This block is the
// software/RTL compatibility handshake for the early OpenMCU platforms.
module omcu_sysctrl #(
  parameter logic [31:0] CHIP_ID = 32'h4f4d_4355,
  parameter logic [15:0] ABI_MAJOR = 16'h0000,
  parameter logic [15:0] ABI_MINOR = 16'h0006,
  parameter logic [31:0] FEATURE_BITS = 32'h0000_00ff,
  parameter logic [31:0] BUILD_ID = 32'h0000_0001,
  parameter integer ROM_BYTES = 4096,
  parameter integer SRAM_BYTES = 32768
) (
  input  logic        req_i,
  input  logic        write_i,
  input  logic [31:0] addr_i,
  output logic        ready_o,
  output logic [31:0] read_data_o,
  output logic        error_o
);

  localparam logic [5:0] REG_CHIP_ID    = 6'h00;
  localparam logic [5:0] REG_ABI        = 6'h01;
  localparam logic [5:0] REG_FEATURES   = 6'h02;
  localparam logic [5:0] REG_BUILD_ID   = 6'h03;
  localparam logic [5:0] REG_MEMORY_KIB = 6'h04;
  localparam logic [15:0] ROM_KIB = ROM_BYTES / 1024;
  localparam logic [15:0] SRAM_KIB = SRAM_BYTES / 1024;

  assign ready_o = req_i;
  // Read-only writes are safely ignored in v0. The register documentation
  // makes their access type explicit, so a later strict debugger can flag it.
  assign error_o = 1'b0;

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CHIP_ID:    read_data_o = CHIP_ID;
      REG_ABI:        read_data_o = {ABI_MAJOR, ABI_MINOR};
      REG_FEATURES:   read_data_o = FEATURE_BITS;
      REG_BUILD_ID:   read_data_o = BUILD_ID;
      REG_MEMORY_KIB: read_data_o = {SRAM_KIB, ROM_KIB};
      default:        read_data_o = '0;
    endcase
  end

endmodule

`default_nettype wire
