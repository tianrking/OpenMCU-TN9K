`default_nettype none
`timescale 1ns / 1ps

// Verifies the 27 MHz reset-release and active-low LED board adapter. This is
// still a digital simulation; it cannot validate pin assignment or LED wiring.
module omcu_tn9k_bringup_top_tb;
  logic clk_27m = 1'b0;
  logic resetn = 1'b0;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [5:0] led_n;
  logic spi_miso = 1'b1;
  logic spi_mosi;
  logic spi_sck;
  logic spi_cs_n;
  logic pwm0;
  tri1 i2c_scl;
  tri1 i2c_sda;
  tri1 [11:0] gpio;

  always #18.518 clk_27m = ~clk_27m;

  omcu_tn9k_bringup_top dut (
    .clk_27m_i(clk_27m),
    .resetn_i(resetn),
    .uart_rx_i(uart_rx),
    .uart_tx_o(uart_tx),
    .led_n_o(led_n),
    .spi0_miso_i(spi_miso),
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
    repeat (4) @(negedge clk_27m);
    resetn = 1'b1;

    repeat (90) @(negedge clk_27m);
    check(led_n == 6'b111110,
          "the board adapter must turn on only active-low LED0 after firmware bring-up");

    // The 12-pad profile must preserve GPIO input and tri-state behavior all
    // the way to the public Tang wrapper, including the newly constrained J5
    // RGB-LCD-shared pads.
    force gpio[11] = 1'b0;
    #1 check(dut.gpio_in[17] == 1'b0,
             "GPIO11 pad input must reach logical GPIO0[17]");
    release gpio[11];
    force dut.system.mmio.gpio0.gpio_oe_q[17] = 1'b1;
    force dut.system.mmio.gpio0.gpio_out_q[17] = 1'b0;
    #1 check(gpio[11] == 1'b0,
             "GPIO11 output-enable must drive the final expansion pad");
    release dut.system.mmio.gpio0.gpio_out_q[17];
    release dut.system.mmio.gpio0.gpio_oe_q[17];

    $display("PASS: omcu_tn9k_bringup_top_tb");
    $finish;
  end
endmodule

`default_nettype wire
