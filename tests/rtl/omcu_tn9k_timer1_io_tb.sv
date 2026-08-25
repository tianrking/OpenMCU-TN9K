`default_nettype none
`timescale 1ns / 1ps

// Runs compiled TIMER1 firmware through PicoRV32, MMIO, the input-only
// pinmux and the final Tang J5 pads.  It is a digital HIL precursor only;
// actual encoder voltage, cable noise and LCD sharing need a physical board.
module omcu_tn9k_timer1_io_tb;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  tri1 [11:0] gpio;
  logic encoder_a = 1'b0;
  logic encoder_b = 1'b0;

  assign gpio[8] = encoder_a;
  assign gpio[9] = encoder_b;

  always #5 clk = ~clk;

  omcu_tn9k_bringup_top #(
    .ROM_INIT_FILE("build/sdk/omcu_timer1_smoke.hex")
  ) dut (
    .clk_27m_i(clk), .resetn_i(resetn), .uart_rx_i(1'b1), .uart_tx_o(), .led_n_o(),
    .spi0_miso_i(1'b1), .spi0_mosi_o(), .spi0_sck_o(), .spi0_cs_n_o(),
    .i2c0_scl_io(), .i2c0_sda_io(), .pwm0_o(), .gpio_io(gpio)
  );

  task automatic drive_encoder(input logic a_value, input logic b_value);
    begin
      encoder_a = a_value;
      encoder_b = b_value;
      repeat (5) @(negedge clk);
    end
  endtask

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

    wait (dut.pinmux_timer1_enable == 1'b1);
    check(gpio[8] == 1'b0 && gpio[9] == 1'b0,
          "TIMER1 pinmux must release both final pads to the external encoder drivers");
    drive_encoder(1'b0, 1'b1);
    drive_encoder(1'b1, 1'b1);
    drive_encoder(1'b1, 1'b0);
    drive_encoder(1'b0, 1'b0);
    check(dut.system.mmio.timer1.encoder_position_q == 32'd4,
          "compiled TIMER1 firmware must count all four forward Gray transitions");
    check(!dut.cpu_trap, "TIMER1 firmware must not trap before encoder integration check");

    $display("PASS: omcu_tn9k_timer1_io_tb");
    $finish;
  end
endmodule

`default_nettype wire
