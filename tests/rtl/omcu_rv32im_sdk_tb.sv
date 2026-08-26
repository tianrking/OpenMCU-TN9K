`default_nettype none
`timescale 1ns / 1ps

// This is deliberately a compiled-SDK gate rather than a hand-coded ROM
// fixture. `omcu_isa_smoke.hex` is built with -march=rv32im and validates
// base integer control plus MUL/DIV/REM execution through the actual SoC.
// The file/module name deliberately follows the current RV32IM product
// profile so test output and CI never suggest that C compression is enabled.
module omcu_rv32im_sdk_tb;
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
    // Keep the simulation MCU geometry identical to the public Tang SDK
    // linker target. This also catches stack accesses near the real SRAM top.
    .ROM_WORDS(2048),
    .SRAM_BYTES(45056),
    .ROM_INIT_FILE("build/sdk/omcu_isa_smoke.hex")
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

  initial begin
    repeat (4) @(negedge clk);
    rst_n = 1'b1;

    // PicoRV32's divide unit is iterative.  This budget covers reset, the
    // .data copy and all signed/unsigned M-extension operations with margin.
    repeat (1200) @(negedge clk);
    check(!cpu_trap, "compiled RV32IM SDK firmware must not trap");
    check(!bus_error_seen, "compiled RV32IM SDK firmware must not access an invalid address");
    check(gpio_oe[0] && gpio_oe[1], "SDK firmware must configure pass/fail GPIO outputs");
    check(gpio_out[0], "compiled RV32IM multiply/divide/remainder checks must pass");
    check(!gpio_out[1], "compiled RV32IM firmware must not raise the failure GPIO");

    $display("PASS: omcu_rv32im_sdk_tb");
    $finish;
  end
endmodule

`default_nettype wire
