`default_nettype none
`timescale 1ns / 1ps

// Exercises optional page decode, IRQCTRL bit assignment and the reviewed
// PULSE0 pad claim. The unit tests cover each counter/filter in more detail.
module omcu_alarm_pulse_fabric_tb;
  localparam logic [31:0] ALARM0_BASE = 32'h4000_c000;
  localparam logic [31:0] TIMER0_BASE = 32'h4000_2000;
  localparam logic [31:0] PULSE0_BASE = 32'h4000_d000;
  localparam logic [31:0] PINMUX_BASE = 32'h4000_b000;
  localparam logic [31:0] IRQ_ALARM0 = 32'h0001_0000;
  localparam logic [31:0] IRQ_PULSE0 = 32'h0002_0000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic [31:0] read_data;
  logic error;
  logic [2:0] pulse;
  logic pinmux_pulse;
  logic [31:0] irq_vector;

  always #5 clk = ~clk;

  omcu_mmio_fabric #(
    .GPIO_COUNT(2), .ROM_BYTES(4096), .SRAM_BYTES(32768),
    .ALARM0_PRESENT(1), .PULSE0_PRESENT(1), .PINMUX_PRESENT(1)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(write_data), .write_strobe_i(write_strobe), .ready_o(),
    .read_data_o(read_data), .error_o(error), .gpio_in_i(2'b00), .gpio_out_o(),
    .gpio_oe_o(), .gpio_irq_o(), .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(),
    .uart1_rx_i(1'b1), .uart1_tx_o(), .uart1_irq_o(), .timer_irq_o(),
    .timer1_capture_a_i(1'b0), .timer1_capture_b_i(1'b0), .timer1_irq_o(),
    .pulse0_i(pulse), .alarm_irq_o(), .pulse0_irq_o(),
    .spi_miso_i(1'b1), .spi_mosi_o(), .spi_sck_o(), .spi_cs_n_o(), .spi_irq_o(),
    .i2c_scl_i(1'b1), .i2c_sda_i(1'b1), .i2c_scl_drive_low_o(), .i2c_sda_drive_low_o(),
    .i2c_irq_o(), .wdt_irq_o(), .wdt_reset_req_o(), .pwm_o(), .pwm1_o(),
    .pinmux_uart1_enable_o(), .pinmux_pwm1_enable_o(), .pinmux_timer1_enable_o(),
    .pinmux_pulse0_enable_o(pinmux_pulse), .irq_vector_o(irq_vector)
  );

  task automatic write_reg(input logic [31:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = address; write_data = value; write_strobe = 4'hf;
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
    pulse = 3'b000;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg(ALARM0_BASE + 32'h1c, 32'd2);
    write_reg(ALARM0_BASE + 32'h0c, 32'h0000_0001);
    write_reg(ALARM0_BASE + 32'h10, 32'h0000_0001);
    write_reg(ALARM0_BASE, 32'h0000_0001);
    write_reg(32'h4000_7004, IRQ_ALARM0 | IRQ_PULSE0);
    // ALARM0 reuses TIMER0's timebase; arm the alarm first, then start a
    // free-running TIMER0 at one system-clock tick per count.
    write_reg(TIMER0_BASE + 32'h04, 32'h0000_0000);
    write_reg(TIMER0_BASE + 32'h08, 32'h0000_0000);
    write_reg(TIMER0_BASE + 32'h0c, 32'hffff_ffff);
    write_reg(TIMER0_BASE, 32'h0000_0005);
    repeat (5) @(negedge clk);
    check((irq_vector & IRQ_ALARM0) != 0,
          "ALARM0 compare must use the dedicated IRQCTRL CPU bit 16");

    write_reg(PULSE0_BASE + 32'h0c, 32'h0000_0000);
    write_reg(PULSE0_BASE + 32'h04, 32'h0000_0000);
    write_reg(PULSE0_BASE, 32'h0000_0003);
    write_reg(PINMUX_BASE, 32'h0000_0008);
    read_reg(PINMUX_BASE, value);
    check(value[3] && pinmux_pulse,
          "PINMUX CTRL bit3 must claim the reviewed PULSE0 input triplet");

    pulse[0] = 1'b1;
    repeat (5) @(negedge clk);
    read_reg(PULSE0_BASE + 32'h10, value);
    check(value[0] && value[2] && (irq_vector & IRQ_PULSE0) != 0,
          "PULSE0 event must decode and reach dedicated IRQCTRL CPU bit 17");

    $display("PASS: omcu_alarm_pulse_fabric_tb");
    $finish;
  end
endmodule

`default_nettype wire
