`default_nettype none
`timescale 1ns / 1ps

// Runs compiled firmware through the real CPU/MMIO path.  It proves that an
// exact SYSCTRL command produces a retained software-reset cause and pending
// Bootloader request at the final Tang wrapper.  It is a digital integration
// test, not proof of UART recovery on a physical board.
module omcu_tn9k_boot_request_tb;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  tri1 i2c_scl;
  tri1 i2c_sda;
  tri1 [11:0] gpio;
  logic [5:0] led_n;
  integer internal_reset_count = 0;

  always #5 clk = ~clk;

  omcu_tn9k_bringup_top #(
    .ROM_INIT_FILE("build/sdk/omcu_boot_request_smoke.hex"),
    .USER_FLASH_PRESENT(1),
    .APPLICATION_BOOT_MODE(1)
  ) dut (
    .clk_27m_i(clk),
    .resetn_i(resetn),
    .uart_rx_i(1'b1), .uart_tx_o(), .led_n_o(led_n),
    .spi0_miso_i(1'b1), .spi0_mosi_o(), .spi0_sck_o(), .spi0_cs_n_o(),
    .i2c0_scl_io(i2c_scl), .i2c0_sda_io(i2c_sda), .pwm0_o(), .gpio_io(gpio)
  );

  always @(negedge dut.sys_rst_ni) begin
    if (resetn) begin
      internal_reset_count = internal_reset_count + 1;
    end
  end

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    resetn = 1'b1;

    wait (dut.reset_count_q == 32'd1);
    wait (dut.sys_rst_ni == 1'b1);
    repeat (500) @(negedge clk);
    check(internal_reset_count == 1,
          "compiled firmware must produce exactly one software reset");
    check(dut.reset_cause_q == 32'h0000_0004,
          "software request must retain SOFTWARE as the next boot cause");
    check(dut.boot_request_pending_q,
          "software request must remain pending until Boot ROM acknowledges it");
    check(dut.system.mmio.sysctrl.run_ticks_q != 64'd0,
          "diagnostic run tick counter must restart and advance after software reset");
    check(led_n[0] == 1'b0,
          "post-reset firmware must observe SOFTWARE cause instead of requesting again");
    check(!dut.cpu_trap, "boot request smoke firmware must not trap");

    $display("PASS: omcu_tn9k_boot_request_tb");
    $finish;
  end
endmodule

`default_nettype wire
