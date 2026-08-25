`default_nettype none
`timescale 1ns / 1ps

// TIMER1's unit test covers filter/Gray semantics.  This test covers its
// public MMIO page, pinmux bit and fixed IRQCTRL CPU bit 15 mapping.
module omcu_timer1_fabric_tb;
  localparam logic [31:0] TIMER1_BASE = 32'h4000_9000;
  localparam logic [31:0] PINMUX_BASE = 32'h4000_b000;
  localparam logic [31:0] IRQ_TIMER1 = 32'h0000_8000;
  localparam logic [31:0] CTRL_CAPTURE_A_ENABLE = 32'h0000_0008;
  localparam logic [31:0] CTRL_IRQ_ENABLE = 32'h0000_0002;
  localparam logic [31:0] STATUS_CAPTURE_A = 32'h0000_0002;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic [31:0] read_data;
  logic error;
  logic capture_a;
  logic capture_b;
  logic pinmux_timer1;
  logic [31:0] irq_vector;

  always #5 clk = ~clk;

  omcu_mmio_fabric #(
    .GPIO_COUNT(2), .ROM_BYTES(4096), .SRAM_BYTES(32768),
    .TIMER1_PRESENT(1), .PINMUX_PRESENT(1)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(write_data), .write_strobe_i(write_strobe), .ready_o(),
    .read_data_o(read_data), .error_o(error), .gpio_in_i(2'b00), .gpio_out_o(),
    .gpio_oe_o(), .gpio_irq_o(), .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(),
    .uart1_rx_i(1'b1), .uart1_tx_o(), .uart1_irq_o(), .timer_irq_o(),
    .timer1_capture_a_i(capture_a), .timer1_capture_b_i(capture_b), .timer1_irq_o(),
    .spi_miso_i(1'b1), .spi_mosi_o(), .spi_sck_o(), .spi_cs_n_o(), .spi_irq_o(),
    .i2c_scl_i(1'b1), .i2c_sda_i(1'b1), .i2c_scl_drive_low_o(), .i2c_sda_drive_low_o(),
    .i2c_irq_o(), .wdt_irq_o(), .wdt_reset_req_o(), .pwm_o(), .pwm1_o(),
    .pinmux_uart1_enable_o(), .pinmux_pwm1_enable_o(),
    .pinmux_timer1_enable_o(pinmux_timer1), .irq_vector_o(irq_vector)
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
    capture_a = 1'b0; capture_b = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    read_reg(TIMER1_BASE, value);
    check(!error && value == 32'h0000_0000,
          "TIMER1 page must decode and reset with every optional mode disabled");
    write_reg(TIMER1_BASE + 32'h10, 32'd0);
    write_reg(TIMER1_BASE + 32'h08, 32'h1020_3040);
    write_reg(TIMER1_BASE, CTRL_CAPTURE_A_ENABLE | CTRL_IRQ_ENABLE);
    write_reg(32'h4000_7004, IRQ_TIMER1);
    write_reg(PINMUX_BASE, 32'h0000_0004);
    read_reg(PINMUX_BASE, value);
    check(value[2] && pinmux_timer1,
          "PINMUX CTRL bit2 must select TIMER1's reviewed input pair");

    capture_a = 1'b1;
    repeat (5) @(negedge clk);
    read_reg(TIMER1_BASE + 32'h20, value);
    check((value & STATUS_CAPTURE_A) != 0,
          "filtered TIMER1 capture A event must be visible through its MMIO page");
    read_reg(TIMER1_BASE + 32'h14, value);
    check(value == 32'h1020_3040,
          "TIMER1 capture timestamp must survive the fabric decode path");
    check((irq_vector & IRQ_TIMER1) != 0,
          "TIMER1 event must reach IRQCTRL fixed CPU bit 15 when enabled");

    write_reg(TIMER1_BASE + 32'h20, STATUS_CAPTURE_A);
    write_reg(32'h4000_7008, IRQ_TIMER1);
    @(negedge clk);
    check((irq_vector & IRQ_TIMER1) == 0,
          "clearing TIMER1 source then IRQCTRL must release CPU IRQ bit 15");

    $display("PASS: omcu_timer1_fabric_tb");
    $finish;
  end
endmodule

`default_nettype wire
