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
    check((dut.system.SYSTEM_FEATURE_BITS & 32'h0000_3f00) == 32'h0000_3f00,
          "Tang wrapper must advertise UART1, TIMER1, PWM1, diagnostics, PINMUX and GPIO expansion");
    check((dut.system.SYSTEM_FEATURE_BITS & 32'h000f_8000) == 32'h000f_8000,
          "Tang wrapper must advertise reliable GPIO, ALARM0, PULSE0, FAULT0 and WDT supervision");
    check(dut.reset_cause_q == 32'h0000_0001 && dut.reset_count_q == 32'd0,
          "external reset must initialize retained diagnostics deterministically");
    check(!dut.system.mmio.sysctrl.boot_ctrl_read[1],
          "bring-up wrapper must not claim the product Bootloader request path");
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

    // The software-visible PINMUX claim must take GPIO10/11 away from the
    // generic output driver at the final board pad.  Force the UART state
    // here because this test's ROM does not issue a UART1 MMIO transaction;
    // omcu_uart1_fabric_tb covers that decoded-register path separately.
    force dut.system.mmio.gpio0.gpio_oe_q[16] = 1'b0;
    force dut.system.mmio.gpio0.gpio_oe_q[17] = 1'b1;
    force dut.system.mmio.gpio0.gpio_out_q[17] = 1'b0;
    force dut.system.mmio.pinmux.uart1_enable_q = 1'b1;
    force dut.system.mmio.uart1.tx_busy_q = 1'b1;
    force dut.system.mmio.uart1.tx_shift_q = 10'b1111111110;
    #1 check(gpio[10] == 1'b0,
             "UART1 pinmux must drive TX low on GPIO10/J5.18 start bit");
    check(gpio[11] == 1'b1,
          "UART1 pinmux must release GPIO11/J5.19 for RX despite GPIO OE");
    force gpio[11] = 1'b0;
    #1 check(dut.system.uart1_rx_i == 1'b0,
             "UART1 RX pad must reach the system UART1 receiver input");
    release gpio[11];
    release dut.system.mmio.uart1.tx_shift_q;
    release dut.system.mmio.uart1.tx_busy_q;
    release dut.system.mmio.pinmux.uart1_enable_q;
    release dut.system.mmio.gpio0.gpio_out_q[17];
    release dut.system.mmio.gpio0.gpio_oe_q[17];
    release dut.system.mmio.gpio0.gpio_oe_q[16];

    // PWM1 owns a disjoint four-pad group only while its pinmux bit is set.
    // Generic GPIO is deliberately forced low here so the high PWM channels
    // prove that the final board adapter, not merely the peripheral, selects
    // the alternate function.
    force dut.system.mmio.gpio0.gpio_oe_q[13:10] = 4'b1111;
    force dut.system.mmio.gpio0.gpio_out_q[13:10] = 4'b0000;
    force dut.system.mmio.pinmux.pwm1_enable_q = 1'b1;
    force dut.pwm1 = 4'b1010;
    #1 check(gpio[4] == 1'b0 && gpio[5] == 1'b1 &&
             gpio[6] == 1'b0 && gpio[7] == 1'b1,
             "PWM1 pinmux must route all four shared-counter channels to J5.12..15");
    release dut.pwm1;
    release dut.system.mmio.pinmux.pwm1_enable_q;
    release dut.system.mmio.gpio0.gpio_out_q[13:10];
    release dut.system.mmio.gpio0.gpio_oe_q[13:10];

    // TIMER1's alternate function is input-only.  It must release both J5
    // pads even when generic GPIO OE is stale, and raw pad levels must reach
    // the system input synchronizers rather than being consumed as GPIO-only.
    force dut.system.mmio.gpio0.gpio_oe_q[15:14] = 2'b11;
    force dut.system.mmio.gpio0.gpio_out_q[15:14] = 2'b00;
    force dut.system.mmio.pinmux.timer1_enable_q = 1'b1;
    #1 check(gpio[8] == 1'b1 && gpio[9] == 1'b1,
             "TIMER1 pinmux must release J5.16/J5.17 despite generic GPIO OE");
    force gpio[8] = 1'b0;
    force gpio[9] = 1'b0;
    #1 check(dut.system.timer1_capture_a_i == 1'b0 &&
             dut.system.timer1_capture_b_i == 1'b0,
             "released TIMER1 pads must reach capture/encoder A and B inputs");
    release gpio[9];
    release gpio[8];
    release dut.system.mmio.pinmux.timer1_enable_q;
    release dut.system.mmio.gpio0.gpio_out_q[15:14];
    release dut.system.mmio.gpio0.gpio_oe_q[15:14];

    // PULSE0 is a reviewed three-input function on GPIO0..2 / J5.8..10. Its
    // pinmux claim is input-only and must win even if generic GPIO OE is stale.
    force dut.system.mmio.gpio0.gpio_oe_q[8:6] = 3'b111;
    force dut.system.mmio.gpio0.gpio_out_q[8:6] = 3'b000;
    force dut.system.mmio.pinmux.pulse0_enable_q = 1'b1;
    #1 check(gpio[2:0] == 3'b111,
             "PULSE0 pinmux must release J5.8..10 despite generic GPIO output-enable");
    force gpio[0] = 1'b0;
    #1 check(dut.system.pulse0_i[0] == 1'b0,
             "released PULSE0 channel 0 pad must reach the system input synchronizer");
    release gpio[0];
    release dut.system.mmio.pinmux.pulse0_enable_q;
    release dut.system.mmio.gpio0.gpio_out_q[8:6];
    release dut.system.mmio.gpio0.gpio_oe_q[8:6];

    // FAULT0 is the separately reviewed J5.11 input-only interlock.  A
    // pinmux claim must release the final pad and pass the raw pad level into
    // the monitor synchronizer, even before its programmable filter acts.
    force dut.system.mmio.gpio0.gpio_oe_q[9] = 1'b1;
    force dut.system.mmio.gpio0.gpio_out_q[9] = 1'b0;
    force dut.system.mmio.pinmux.fault0_enable_q = 1'b1;
    #1 check(gpio[3] == 1'b1,
             "FAULT0 pinmux must release J5.11 despite generic GPIO output-enable");
    force gpio[3] = 1'b0;
    #1 check(dut.system.fault0_i == 1'b0,
             "released FAULT0 pad must reach the system fault monitor input");
    release gpio[3];
    release dut.system.mmio.pinmux.fault0_enable_q;
    release dut.system.mmio.gpio0.gpio_out_q[9];
    release dut.system.mmio.gpio0.gpio_oe_q[9];

    // A latched trip applies its selected gates after every normal pinmux
    // decision: PWM outputs go low and a selected generic GPIO pad is high-Z.
    force dut.system.mmio.gpio0.gpio_oe_q[6] = 1'b1;
    force dut.system.mmio.gpio0.gpio_out_q[6] = 1'b1;
    force dut.pwm0_raw = 1'b1;
    force dut.pwm1_raw = 4'b1111;
    force dut.system.mmio.fault0.trip_q = 1'b1;
    force dut.system.mmio.fault0.gate_pwm0_q = 1'b1;
    force dut.system.mmio.fault0.gate_pwm1_q = 1'b1;
    force dut.system.mmio.fault0.gate_gpio_q = 1'b1;
    force dut.system.mmio.fault0.gpio_hiz_mask_q[6] = 1'b1;
    #1 check(pwm0 == 1'b0 && dut.pwm1 == 4'b0000 && gpio[0] == 1'b1,
             "FAULT0 trip must force PWM low and selected GPIO output-enable high-Z");
    release dut.system.mmio.fault0.gpio_hiz_mask_q[6];
    release dut.system.mmio.fault0.gate_gpio_q;
    release dut.system.mmio.fault0.gate_pwm1_q;
    release dut.system.mmio.fault0.gate_pwm0_q;
    release dut.system.mmio.fault0.trip_q;
    release dut.pwm1_raw;
    release dut.pwm0_raw;
    release dut.system.mmio.gpio0.gpio_out_q[6];
    release dut.system.mmio.gpio0.gpio_oe_q[6];

    $display("PASS: omcu_tn9k_bringup_top_tb");
    $finish;
  end
endmodule

`default_nettype wire
