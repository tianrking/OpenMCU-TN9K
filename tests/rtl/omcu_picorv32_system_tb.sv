`default_nettype none
`timescale 1ns / 1ps

// Executes a five-instruction RV32I image through the real CPU adapter.
// The image enables GPIO0[0] and drives it high, then loops forever.
module omcu_picorv32_system_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [3:0] gpio_in = 4'b0000;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [3:0] gpio_out;
  logic [3:0] gpio_oe;
  logic gpio_irq;
  logic timer_irq;
  logic cpu_trap;
  logic bus_error;

  always #5 clk = ~clk;

  omcu_picorv32_system #(
    .GPIO_COUNT(4),
    .ROM_WORDS(16),
    .SRAM_BYTES(1024),
    .ROM_INIT_FILE("tests/data/gpio_bringup.hex")
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .gpio_in_i(gpio_in),
    .gpio_out_o(gpio_out),
    .gpio_oe_o(gpio_oe),
    .gpio_irq_o(gpio_irq),
    .uart_rx_i(uart_rx),
    .uart_tx_o(uart_tx),
    .uart_irq_o(),
    .timer_irq_o(timer_irq),
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

  initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    repeat (80) @(negedge clk);
    check(!cpu_trap, "the GPIO bring-up firmware must not trap");
    check(!bus_error, "the GPIO bring-up firmware must not access an invalid address");
    check(gpio_oe[0], "firmware must enable GPIO0[0] output");
    check(gpio_out[0], "firmware must drive GPIO0[0] high");

    $display("PASS: omcu_picorv32_system_tb");
    $finish;
  end
endmodule

`default_nettype wire
