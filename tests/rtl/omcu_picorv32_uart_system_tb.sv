`default_nettype none
`timescale 1ns / 1ps

// Executes RV32I firmware that configures UART0 through the OpenMCU fabric and
// sends 0xA5 using a four-clock bit period.
module omcu_picorv32_uart_system_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [3:0] gpio_out;
  logic [3:0] gpio_oe;
  logic uart_tx;
  logic cpu_trap;
  logic bus_error;
  logic bus_error_seen = 1'b0;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (bus_error) begin
      bus_error_seen <= 1'b1;
    end
  end

  omcu_picorv32_system #(
    .GPIO_COUNT(4),
    .ROM_WORDS(16),
    .SRAM_BYTES(1024),
    .ROM_INIT_FILE("tests/data/uart_bringup.hex")
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .gpio_in_i(4'b0000),
    .gpio_out_o(gpio_out),
    .gpio_oe_o(gpio_oe),
    .gpio_irq_o(),
    .uart_rx_i(1'b1),
    .uart_tx_o(uart_tx),
    .uart_irq_o(),
    .timer_irq_o(),
    .cpu_trap_o(cpu_trap),
    .bus_error_o(bus_error)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic check_tx_after_one_bit(input logic expected, input string message);
    begin
      repeat (4) @(negedge clk);
      check(uart_tx == expected, message);
    end
  endtask

  initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    wait (uart_tx == 1'b0);
    check(!cpu_trap, "UART firmware must not trap before transmitting");
    // The wait releases in the launch clock's time step; move to the first
    // following negative edge so the bit-period helper counts full periods.
    @(negedge clk);
    check(uart_tx == 1'b0, "firmware UART transmission must begin with a start bit");
    check_tx_after_one_bit(1'b1, "firmware UART bit 0 must be high");
    check_tx_after_one_bit(1'b0, "firmware UART bit 1 must be low");
    check_tx_after_one_bit(1'b1, "firmware UART bit 2 must be high");
    check_tx_after_one_bit(1'b0, "firmware UART bit 3 must be low");
    check_tx_after_one_bit(1'b0, "firmware UART bit 4 must be low");
    check_tx_after_one_bit(1'b1, "firmware UART bit 5 must be high");
    check_tx_after_one_bit(1'b0, "firmware UART bit 6 must be low");
    check_tx_after_one_bit(1'b1, "firmware UART bit 7 must be high");
    check_tx_after_one_bit(1'b1, "firmware UART stop bit must be high");
    repeat (4) @(negedge clk);
    check(!bus_error_seen, "firmware UART transaction path must not hit an invalid address");

    $display("PASS: omcu_picorv32_uart_system_tb");
    $finish;
  end
endmodule

`default_nettype wire
