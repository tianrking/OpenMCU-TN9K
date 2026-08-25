`default_nettype none
`timescale 1ns / 1ps

// Protects the public PWM1 and PINMUX address decode.  omcu_pwm1_tb verifies
// waveform details; this test proves the optional peripheral is reachable as
// one OpenMCU fabric feature rather than a disconnected RTL block.
module omcu_pwm1_fabric_tb;
  localparam logic [31:0] PWM1_BASE = 32'h4000_a000;
  localparam logic [31:0] PINMUX_BASE = 32'h4000_b000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic ready;
  logic [31:0] read_data;
  logic error;
  logic [3:0] pwm1;
  logic pinmux_pwm1;

  always #5 clk = ~clk;

  omcu_mmio_fabric #(
    .GPIO_COUNT(2),
    .ROM_BYTES(4096),
    .SRAM_BYTES(32768),
    .PWM1_PRESENT(1),
    .PINMUX_PRESENT(1)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(write_data), .write_strobe_i(write_strobe), .ready_o(ready),
    .read_data_o(read_data), .error_o(error), .gpio_in_i(2'b00),
    .gpio_out_o(), .gpio_oe_o(), .gpio_irq_o(), .uart_rx_i(1'b1), .uart_tx_o(),
    .uart_irq_o(), .uart1_rx_i(1'b1), .uart1_tx_o(), .uart1_irq_o(),
    .timer_irq_o(), .spi_miso_i(1'b1), .spi_mosi_o(), .spi_sck_o(), .spi_cs_n_o(),
    .spi_irq_o(), .i2c_scl_i(1'b1), .i2c_sda_i(1'b1), .i2c_scl_drive_low_o(),
    .i2c_sda_drive_low_o(), .i2c_irq_o(), .wdt_irq_o(), .wdt_reset_req_o(),
    .pwm_o(), .pwm1_o(pwm1), .pinmux_uart1_enable_o(),
    .pinmux_pwm1_enable_o(pinmux_pwm1), .pinmux_timer1_enable_o(), .irq_vector_o()
  );

  task automatic write_reg(input logic [31:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = address;
      write_data = value; write_strobe = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; write_data = '0; write_strobe = '0;
    end
  endtask

  task automatic read_reg(input logic [31:0] address, output logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b0; addr = address; write_data = '0; write_strobe = '0;
      #1 value = read_data;
      @(negedge clk);
      req = 1'b0; addr = '0;
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

  logic [31:0] value;

  initial begin
    req = 1'b0; write = 1'b0; addr = '0; write_data = '0; write_strobe = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    read_reg(PWM1_BASE, value);
    check(!error && value == 32'h0000_0000 && pwm1 == 4'b0000,
          "PWM1 page must decode with all four outputs safely low after reset");
    write_reg(PWM1_BASE + 32'h04, 32'd0);
    write_reg(PWM1_BASE + 32'h08, 32'hbeef_0003);
    read_reg(PWM1_BASE + 32'h08, value);
    check(value == 32'h0000_0003,
          "PWM1 period must retain only the documented low 16 bits through fabric");
    write_reg(PWM1_BASE + 32'h0c, 32'd1);
    write_reg(PWM1_BASE + 32'h10, 32'd2);
    write_reg(PWM1_BASE + 32'h14, 32'd0);
    write_reg(PWM1_BASE + 32'h18, 32'd4);
    write_reg(PWM1_BASE, 32'h0000_0001);
    check(pwm1 == 4'b1011,
          "PWM1 must expose four shared-phase channel outputs through the fabric");
    read_reg(PWM1_BASE, value);
    check(value[0], "PWM1 CTRL.ENABLE must be readable through the MMIO fabric");

    write_reg(PINMUX_BASE, 32'h0000_0002);
    read_reg(PINMUX_BASE, value);
    check(value[1] && pinmux_pwm1,
          "PINMUX CTRL bit1 must select the approved PWM1 pad group");

    write_reg(PWM1_BASE, 32'h0000_00f0);
    check(pwm1 == 4'b0000,
          "PWM1 disabled outputs must remain low even when every invert bit is set");

    $display("PASS: omcu_pwm1_fabric_tb");
    $finish;
  end
endmodule

`default_nettype wire
