`default_nettype none
`timescale 1ns / 1ps

// Exercises the optional UART1 page through the real MMIO decoder and its
// seventh IRQCTRL source.  omcu_uart_tb separately covers the serial engine
// itself; this test protects the public page, IRQ bit and pinmux ABI wiring.
module omcu_uart1_fabric_tb;
  localparam logic [31:0] UART1_BASE = 32'h4000_8000;
  localparam logic [31:0] PINMUX_BASE = 32'h4000_b000;
  localparam logic [31:0] IRQ_UART1 = 32'h0000_4000;

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
  logic [1:0] gpio_in;
  logic [1:0] gpio_out;
  logic [1:0] gpio_oe;
  logic uart1_rx;
  logic uart1_tx;
  logic [31:0] irq_vector;
  logic pinmux_uart1;

  always #5 clk = ~clk;

  omcu_mmio_fabric #(
    .GPIO_COUNT(2),
    .ROM_BYTES(4096),
    .SRAM_BYTES(32768),
    .UART1_PRESENT(1),
    .PINMUX_PRESENT(1)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_i(req),
    .write_i(write),
    .addr_i(addr),
    .write_data_i(write_data),
    .write_strobe_i(write_strobe),
    .ready_o(ready),
    .read_data_o(read_data),
    .error_o(error),
    .gpio_in_i(gpio_in),
    .gpio_out_o(gpio_out),
    .gpio_oe_o(gpio_oe),
    .gpio_irq_o(),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .uart_irq_o(),
    .uart1_rx_i(uart1_rx),
    .uart1_tx_o(uart1_tx),
    .uart1_irq_o(),
    .timer_irq_o(),
    .spi_miso_i(1'b1),
    .spi_mosi_o(),
    .spi_sck_o(),
    .spi_cs_n_o(),
    .spi_irq_o(),
    .i2c_scl_i(1'b1),
    .i2c_sda_i(1'b1),
    .i2c_scl_drive_low_o(),
    .i2c_sda_drive_low_o(),
    .i2c_irq_o(),
    .wdt_irq_o(),
    .wdt_reset_req_o(),
    .pwm_o(),
    .pinmux_uart1_enable_o(pinmux_uart1),
    .pinmux_pwm1_enable_o(),
    .pinmux_timer1_enable_o(),
    .irq_vector_o(irq_vector)
  );

  task automatic write_reg(input logic [31:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      addr = address;
      write_data = value;
      write_strobe = 4'hf;
      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
      addr = '0;
      write_data = '0;
      write_strobe = '0;
    end
  endtask

  task automatic read_reg(input logic [31:0] address, output logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b0;
      addr = address;
      write_data = '0;
      write_strobe = '0;
      #1 value = read_data;
      @(negedge clk);
      req = 1'b0;
      addr = '0;
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

  task automatic drive_rx_bit(input logic value);
    begin
      uart1_rx = value;
      repeat (4) @(negedge clk);
    end
  endtask

  task automatic drive_rx_byte(input logic [7:0] value);
    integer index;
    begin
      uart1_rx = 1'b0;
      repeat (4) @(negedge clk);
      for (index = 0; index < 8; index = index + 1) begin
        drive_rx_bit(value[index]);
      end
      drive_rx_bit(1'b1);
      repeat (4) @(negedge clk);
    end
  endtask

  logic [31:0] value;

  initial begin
    req = 1'b0;
    write = 1'b0;
    addr = '0;
    write_data = '0;
    write_strobe = '0;
    gpio_in = '0;
    uart1_rx = 1'b1;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // The optional decoder is real only when UART1_PRESENT is asserted.
    read_reg(UART1_BASE + 32'h04, value);
    check(!error && value == 32'h0000_0000,
          "UART1 page must decode and reset with its transmitter disabled");
    write_reg(UART1_BASE + 32'h0c, 32'h0000_0007);
    write_reg(UART1_BASE + 32'h08, 32'h0000_0003);
    read_reg(UART1_BASE + 32'h04, value);
    check(value[0], "UART1 STATUS.TX_READY must be visible through the MMIO fabric");

    write_reg(PINMUX_BASE, 32'h0000_0001);
    read_reg(PINMUX_BASE, value);
    check(value[0] && pinmux_uart1,
          "PINMUX.CTRL bit0 must claim the approved UART1 pad group");

    write_reg(UART1_BASE, 32'h0000_00a5);
    check(uart1_tx == 1'b0,
          "UART1 TX start bit must leave the MMIO fabric immediately");

    // RX_VALID feeds source index 6, which is fixed at CPU IRQ bit 14.
    write_reg(32'h4000_7004, IRQ_UART1);
    drive_rx_byte(8'h3c);
    read_reg(UART1_BASE + 32'h04, value);
    check(value[1], "UART1 RX byte must become valid through the decoded page");
    check((irq_vector & IRQ_UART1) != 0,
          "UART1 RX IRQ must use the public CPU IRQ bit 14");
    read_reg(UART1_BASE, value);
    check(value[7:0] == 8'h3c,
          "UART1 DATA read must return the received byte");
    write_reg(32'h4000_7008, IRQ_UART1);
    @(negedge clk);
    check((irq_vector & IRQ_UART1) == 0,
          "clearing UART1 source after consuming DATA must release IRQCTRL bit 14");

    $display("PASS: omcu_uart1_fabric_tb");
    $finish;
  end
endmodule

`default_nettype wire
