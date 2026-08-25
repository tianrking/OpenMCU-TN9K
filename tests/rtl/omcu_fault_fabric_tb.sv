`default_nettype none
`timescale 1ns / 1ps

module omcu_fault_fabric_tb;
  localparam logic [31:0] FAULT0_BASE = 32'h4000_e000;
  localparam logic [31:0] PINMUX_BASE = 32'h4000_b000;
  localparam logic [31:0] IRQ_FAULT0 = 32'h0004_0000;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic [31:0] read_data;
  logic fault_in;
  logic pinmux_fault;
  logic pwm0_kill;
  logic pwm1_kill;
  logic [1:0] gpio_hiz;
  logic [31:0] irq_vector;

  always #5 clk = ~clk;

  omcu_mmio_fabric #(
    .GPIO_COUNT(2), .ROM_BYTES(4096), .SRAM_BYTES(32768),
    .FAULT0_PRESENT(1), .PINMUX_PRESENT(1)
  ) dut (
    .clk_i(clk), .rst_ni(rst_n), .reset_cause_i(32'h0000_0002),
    .reset_count_i(32'h0000_0003), .boot_request_pending_i(1'b0),
    .software_boot_request_o(), .boot_request_ack_o(), .req_i(req), .write_i(write),
    .addr_i(addr), .write_data_i(write_data), .write_strobe_i(write_strobe),
    .ready_o(), .read_data_o(read_data), .error_o(), .gpio_in_i(2'b10), .gpio_out_o(),
    .gpio_oe_o(), .gpio_irq_o(), .uart_rx_i(1'b1), .uart_tx_o(), .uart_irq_o(),
    .uart1_rx_i(1'b1), .uart1_tx_o(), .uart1_irq_o(), .timer_irq_o(),
    .timer1_capture_a_i(1'b0), .timer1_capture_b_i(1'b0), .timer1_irq_o(),
    .pulse0_i(3'b000), .alarm_irq_o(), .pulse0_irq_o(), .fault0_i(fault_in),
    .fault0_irq_o(), .spi_miso_i(1'b1), .spi_mosi_o(), .spi_sck_o(), .spi_cs_n_o(),
    .spi_irq_o(), .i2c_scl_i(1'b1), .i2c_sda_i(1'b1), .i2c_scl_drive_low_o(),
    .i2c_sda_drive_low_o(), .i2c_irq_o(), .wdt_irq_o(), .wdt_reset_req_o(),
    .pwm_o(), .pwm1_o(), .pinmux_uart1_enable_o(), .pinmux_pwm1_enable_o(),
    .pinmux_timer1_enable_o(), .pinmux_pulse0_enable_o(),
    .pinmux_fault0_enable_o(pinmux_fault), .fault_pwm0_kill_o(pwm0_kill),
    .fault_pwm1_kill_o(pwm1_kill), .fault_gpio_hiz_mask_o(gpio_hiz),
    .irq_vector_o(irq_vector)
  );

  task automatic write_reg(input logic [31:0] address, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = address; write_data = value; write_strobe = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; write_data = '0; write_strobe = '0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin if (!condition) begin $error("%s", message); $fatal(1); end end
  endtask

  initial begin
    req = 0; write = 0; addr = '0; write_data = '0; write_strobe = '0; fault_in = 0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg(FAULT0_BASE + 32'h04, 32'h0000_0000);
    write_reg(FAULT0_BASE + 32'h08, 32'h0000_0002);
    write_reg(FAULT0_BASE, 32'h0000_003f);
    write_reg(32'h4000_7004, IRQ_FAULT0);
    fault_in = 1'b1;
    repeat (5) @(negedge clk);
    check(!pwm0_kill && !pwm1_kill && gpio_hiz == 2'b00,
          "fabric must not arm FAULT0 before its reviewed pinmux claim");

    write_reg(PINMUX_BASE, 32'h0000_0010);
    repeat (3) @(negedge clk);
    check(pinmux_fault && pwm0_kill && pwm1_kill && gpio_hiz == 2'b10 &&
          (irq_vector & IRQ_FAULT0) != 0,
          "FAULT0 must decode, gate outputs and reach fixed CPU IRQ bit 18");

    $display("PASS: omcu_fault_fabric_tb");
    $finish;
  end
endmodule

`default_nettype wire
