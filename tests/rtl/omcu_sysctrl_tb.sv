`default_nettype none
`timescale 1ns / 1ps

module omcu_sysctrl_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] address;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic ready;
  logic [31:0] read_data;
  logic error;
  logic [31:0] reset_cause = 32'h0000_0001;
  logic [31:0] reset_count = 32'h0000_0000;
  logic boot_request_pending = 1'b0;
  logic software_boot_request;
  logic boot_request_ack;

  always #5 clk = ~clk;

  omcu_sysctrl #(
    .BUILD_ID(32'h2026_0825),
    .ROM_BYTES(8192),
    .SRAM_BYTES(24576),
    .FEATURE_BITS(32'h0000_08ff),
    .BOOT_REQUEST_PRESENT(1)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_i(req),
    .write_i(write),
    .addr_i(address),
    .write_data_i(write_data),
    .write_strobe_i(write_strobe),
    .ready_o(ready),
    .read_data_o(read_data),
    .error_o(error),
    .reset_cause_i(reset_cause),
    .reset_count_i(reset_count),
    .boot_request_pending_i(boot_request_pending),
    .software_boot_request_o(software_boot_request),
    .boot_request_ack_o(boot_request_ack)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic check_read(
    input logic [31:0] offset,
    input logic [31:0] expected,
    input string message
  );
    begin
      req = 1'b1;
      write = 1'b0;
      address = offset;
      #1;
      check(ready, "SYSCTRL must acknowledge a valid transaction");
      check(!error, "SYSCTRL reads must not report an error");
      check(read_data == expected, message);
    end
  endtask

  task automatic write_boot_ctrl(
    input logic [31:0] value,
    input logic [3:0] strobe
  );
    begin
      req = 1'b1;
      write = 1'b1;
      address = 32'h0000_0024;
      write_data = value;
      write_strobe = strobe;
      @(posedge clk);
      #1;
      write = 1'b0;
    end
  endtask

  initial begin
    req = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    write_strobe = '0;

    repeat (2) @(negedge clk);
    rst_n = 1'b1;
    repeat (5) @(posedge clk);

    check_read(32'h0000_0000, 32'h4f4d_4355, "chip identifier must be OMCU");
    check_read(32'h0000_0004, 32'h0000_0006, "ABI version must encode v0.6");
    check_read(32'h0000_0008, 32'h0000_08ff,
               "feature bits must advertise diagnostics with the base peripherals");
    check_read(32'h0000_000c, 32'h2026_0825, "build identifier must be parameterized");
    check_read(32'h0000_0010, 32'h0018_0008, "memory register must report SRAM/ROM KiB");
    address = 32'h0000_0018;
    #1 check(read_data != 32'h0000_0000,
             "run tick counter must advance while the SoC reset is released");

    reset_cause = 32'h0000_0004;
    reset_count = 32'd7;
    boot_request_pending = 1'b1;
    check_read(32'h0000_0014, 32'h0000_0004,
               "reset cause must be supplied by the retained platform sequencer");
    check_read(32'h0000_0020, 32'd7,
               "reset count must be supplied by the retained platform sequencer");
    check_read(32'h0000_0024, 32'h0000_0003,
               "boot control must report pending and supported status bits");

    write_boot_ctrl(32'hb007_10ad, 4'b0011);
    check(!software_boot_request,
          "partial writes must never accidentally request a bootloader reset");
    write_boot_ctrl(32'h0000_0000, 4'b1111);
    check(!software_boot_request,
          "wrong full-word magic must not request a bootloader reset");
    write_boot_ctrl(32'hb007_10ad, 4'b1111);
    check(software_boot_request,
          "exact request magic must create a one-cycle software reset request");
    @(posedge clk);
    #1 check(!software_boot_request,
             "software bootloader request must return low after one cycle");

    write_boot_ctrl(32'hacce_5501, 4'b1111);
    check(boot_request_ack,
          "exact acknowledgement magic must create a one-cycle clear request");
    @(posedge clk);
    #1 check(!boot_request_ack,
             "bootloader acknowledgement must return low after one cycle");

    $display("PASS: omcu_sysctrl_tb");
    $finish;
  end
endmodule

`default_nettype wire
