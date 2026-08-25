`default_nettype none
`timescale 1ns / 1ps

// Executes compiled firmware through PicoRV32, the MMIO fabric, pinmux and
// final Tang expansion pads.  This remains digital simulation, not a proof of
// the RGB-LCD-shared J5 electrical net or any attached power stage.
module omcu_tn9k_pwm1_io_tb;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  tri1 [11:0] gpio;
  logic [3:0] high_seen = 4'b0000;
  logic [3:0] low_seen = 4'b0000;

  always #5 clk = ~clk;

  omcu_tn9k_bringup_top #(
    .ROM_INIT_FILE("build/sdk/omcu_pwm1_smoke.hex")
  ) dut (
    .clk_27m_i(clk),
    .resetn_i(resetn),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .led_n_o(),
    .spi0_miso_i(1'b1),
    .spi0_mosi_o(),
    .spi0_sck_o(),
    .spi0_cs_n_o(),
    .i2c0_scl_io(),
    .i2c0_sda_io(),
    .pwm0_o(),
    .gpio_io(gpio)
  );

  always @(gpio) begin
    if (resetn && dut.sys_rst_ni && dut.pinmux_pwm1_enable) begin
      if (gpio[4] === 1'b1) high_seen[0] <= 1'b1;
      if (gpio[5] === 1'b1) high_seen[1] <= 1'b1;
      if (gpio[6] === 1'b1) high_seen[2] <= 1'b1;
      if (gpio[7] === 1'b1) high_seen[3] <= 1'b1;
      if (gpio[4] === 1'b0) low_seen[0] <= 1'b1;
      if (gpio[5] === 1'b0) low_seen[1] <= 1'b1;
      if (gpio[6] === 1'b0) low_seen[2] <= 1'b1;
      if (gpio[7] === 1'b0) low_seen[3] <= 1'b1;
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

    wait (dut.pinmux_pwm1_enable == 1'b1);
    repeat (80) @(negedge clk);
    check(high_seen == 4'b1111,
          "compiled PWM1 firmware must drive every configured channel high at its Tang pad");
    check(low_seen == 4'b1111,
          "compiled PWM1 firmware must drive every configured channel low at its Tang pad");
    check(!dut.cpu_trap, "PWM1 firmware must not trap before its pad waveform check");

    $display("PASS: omcu_tn9k_pwm1_io_tb");
    $finish;
  end
endmodule

`default_nettype wire
