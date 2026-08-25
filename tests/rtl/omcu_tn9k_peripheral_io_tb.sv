`default_nettype none
`timescale 1ns / 1ps

// End-to-end board-wrapper test.  It runs the compiled SDK peripheral image
// through the same Tang Nano top used by P&R and proves that SPI0, PWM0 and the
// expansion GPIO tri-state adapter leave the SoC on real top-level ports.
// This is not an electrical/connector validation; the hardware checklist must
// still be completed on a physical Tang Nano 9K.
module omcu_tn9k_peripheral_io_tb;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic uart_tx;
  logic [5:0] led_n;
  logic spi_mosi;
  logic spi_sck;
  logic spi_cs_n;
  logic pwm0;
  logic spi_transfer_seen = 1'b0;
  logic pwm_high_seen = 1'b0;
  logic pwm_low_seen = 1'b0;
  tri1 i2c_scl;
  tri1 i2c_sda;
  tri1 [11:0] gpio;

  always #5 clk = ~clk;

  always @(negedge spi_cs_n) begin
    if (resetn && dut.sys_rst_ni) begin
      spi_transfer_seen <= 1'b1;
    end
  end

  always @(posedge pwm0) begin
    if (resetn && dut.sys_rst_ni) begin
      pwm_high_seen <= 1'b1;
    end
  end

  always @(negedge pwm0) begin
    if (resetn && dut.sys_rst_ni) begin
      pwm_low_seen <= 1'b1;
    end
  end

  omcu_tn9k_bringup_top #(
    .ROM_INIT_FILE("build/sdk/omcu_peripheral_smoke.hex")
  ) dut (
    .clk_27m_i(clk),
    .resetn_i(resetn),
    .uart_rx_i(1'b1),
    .uart_tx_o(uart_tx),
    .led_n_o(led_n),
    .spi0_miso_i(1'b1),
    .spi0_mosi_o(spi_mosi),
    .spi0_sck_o(spi_sck),
    .spi0_cs_n_o(spi_cs_n),
    .i2c0_scl_io(i2c_scl),
    .i2c0_sda_io(i2c_sda),
    .pwm0_o(pwm0),
    .gpio_io(gpio)
  );

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

    wait (led_n[0] === 1'b0);
    check(spi_transfer_seen,
          "compiled SDK SPI0 transfer must reach the Tang Nano SPI0 chip-select pad");
    check(pwm_high_seen && pwm_low_seen,
          "compiled SDK PWM0 configuration must toggle the Tang Nano PWM0 pad");
    // The SDK smoke deliberately claims GPIO0/1 as PASS/FAIL outputs (01);
    // every other reviewed J5 pad must still be released at the board adapter.
    // tri1 pulls a released pad high, so bit1 being low proves this assertion
    // distinguishes the driven FAIL pin from twelve passive pull-ups.
    check(gpio[11:2] === 10'h3ff && gpio[1:0] === 2'b01,
          "SDK PASS/FAIL pins must drive 01 while unused J5 GPIO2..11 stay high-impedance");
    check(i2c_scl === 1'b1 && i2c_sda === 1'b1,
          "idle I2C0 board pads must be released rather than actively driven high");
    check(!dut.cpu_trap, "peripheral SDK firmware must not trap before PASS");

    $display("PASS: omcu_tn9k_peripheral_io_tb");
    $finish;
  end
endmodule

`default_nettype wire
