`default_nettype none

// Hardware identity, capability metadata and reset-domain diagnostics.  The
// reset cause/count and bootloader-request latch itself live in the board
// wrapper so they survive an internal watchdog or software reset; this block
// only exposes them through the stable MMIO ABI and owns the running tick
// counter plus the two magic command pulses.
module omcu_sysctrl #(
  parameter logic [31:0] CHIP_ID = 32'h4f4d_4355,
  parameter logic [15:0] ABI_MAJOR = 16'h0000,
  parameter logic [15:0] ABI_MINOR = 16'h0008,
  parameter logic [31:0] FEATURE_BITS = 32'h0008_80ff,
  parameter logic [31:0] BUILD_ID = 32'h0000_0001,
  parameter integer ROM_BYTES = 4096,
  parameter integer SRAM_BYTES = 32768,
  parameter integer BOOT_REQUEST_PRESENT = 0
) (
  input  logic        clk_i,
  input  logic        rst_ni,
  input  logic        req_i,
  input  logic        write_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] write_data_i,
  input  logic [3:0]  write_strobe_i,
  output logic        ready_o,
  output logic [31:0] read_data_o,
  output logic        error_o,

  input  logic [31:0] reset_cause_i,
  input  logic [31:0] reset_count_i,
  input  logic        boot_request_pending_i,
  output logic        software_boot_request_o,
  output logic        boot_request_ack_o,

  // Shared timestamp consumers use the same low word that software reads at
  // SYSCTRL.RUN_TICKS_LO.  The full 64-bit counter remains the MMIO ABI.
  output logic [31:0] run_ticks_o
);

  localparam logic [5:0] REG_CHIP_ID    = 6'h00;
  localparam logic [5:0] REG_ABI        = 6'h01;
  localparam logic [5:0] REG_FEATURES   = 6'h02;
  localparam logic [5:0] REG_BUILD_ID   = 6'h03;
  localparam logic [5:0] REG_MEMORY_KIB = 6'h04;
  localparam logic [5:0] REG_RESET_CAUSE = 6'h05;
  localparam logic [5:0] REG_RUN_TICKS_LO = 6'h06;
  localparam logic [5:0] REG_RUN_TICKS_HI = 6'h07;
  localparam logic [5:0] REG_RESET_COUNT = 6'h08;
  localparam logic [5:0] REG_BOOT_CTRL = 6'h09;
  localparam logic [15:0] ROM_KIB = ROM_BYTES / 1024;
  localparam logic [15:0] SRAM_KIB = SRAM_BYTES / 1024;
  localparam logic [31:0] BOOT_REQUEST_MAGIC = 32'hb007_10ad;
  localparam logic [31:0] BOOT_REQUEST_ACK_MAGIC = 32'hacce_5501;

  logic [63:0] run_ticks_q;
  logic [31:0] boot_ctrl_read;

  assign ready_o = req_i;
  // Identity/geometry writes are safely ignored. BOOT_CTRL is intentionally
  // the only write side effect and requires an exact, full-word magic value.
  assign error_o = 1'b0;
  assign run_ticks_o = run_ticks_q[31:0];

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      run_ticks_q <= 64'h0000_0000_0000_0000;
      software_boot_request_o <= 1'b0;
      boot_request_ack_o <= 1'b0;
    end else begin
      run_ticks_q <= run_ticks_q + 64'd1;
      software_boot_request_o <= 1'b0;
      boot_request_ack_o <= 1'b0;

      if ((BOOT_REQUEST_PRESENT != 0) && req_i && write_i &&
          (addr_i[7:2] == REG_BOOT_CTRL) && (write_strobe_i == 4'b1111)) begin
        if (write_data_i == BOOT_REQUEST_MAGIC) begin
          software_boot_request_o <= 1'b1;
        end else if (write_data_i == BOOT_REQUEST_ACK_MAGIC) begin
          boot_request_ack_o <= 1'b1;
        end
      end
    end
  end

  always_comb begin
    boot_ctrl_read = '0;
    boot_ctrl_read[0] = (BOOT_REQUEST_PRESENT != 0) && boot_request_pending_i;
    boot_ctrl_read[1] = (BOOT_REQUEST_PRESENT != 0);

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CHIP_ID:    read_data_o = CHIP_ID;
      REG_ABI:        read_data_o = {ABI_MAJOR, ABI_MINOR};
      REG_FEATURES:   read_data_o = FEATURE_BITS;
      REG_BUILD_ID:   read_data_o = BUILD_ID;
      REG_MEMORY_KIB: read_data_o = {SRAM_KIB, ROM_KIB};
      REG_RESET_CAUSE: read_data_o = reset_cause_i;
      REG_RUN_TICKS_LO: read_data_o = run_ticks_q[31:0];
      REG_RUN_TICKS_HI: read_data_o = run_ticks_q[63:32];
      REG_RESET_COUNT: read_data_o = reset_count_i;
      REG_BOOT_CTRL:  read_data_o = boot_ctrl_read;
      default:        read_data_o = '0;
    endcase
  end

endmodule

`default_nettype wire
