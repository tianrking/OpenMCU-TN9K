`default_nettype none
`timescale 1ns / 1ps

// Executes the compiled irq_smoke SDK image through the actual vector at 0x10,
// PicoRV32 custom-IRQ entry/return path, IRQCTRL and TIMER0.  This is the
// product-level gate that prevents a standalone peripheral irq_o from being
// mistaken for a usable firmware interrupt facility.
module omcu_irq_sdk_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [3:0] gpio_out;
  logic [3:0] gpio_oe;
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
    .ROM_WORDS(2048),
    .SRAM_BYTES(45056),
    .ROM_INIT_FILE("build/sdk/omcu_irq_smoke.hex")
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .gpio_in_i(4'b0000),
    .gpio_out_o(gpio_out),
    .gpio_oe_o(gpio_oe),
    .gpio_irq_o(),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .uart_irq_o(),
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

    // This includes startup relocation, timer compare, IRQCTRL latching,
    // vector entry, full register preservation, C dispatch and RETIRQ.
    // Startup clears the complete 44 KiB SRAM image, and the wrapper saves
    // the full application register file. Leave a generous deterministic
    // budget for boot + IRQ + RETIRQ rather than sampling midway through it.
    repeat (20000) @(negedge clk);
    check(!cpu_trap, "compiled interrupt firmware must return from the IRQ without trapping");
    check(!bus_error_seen, "compiled interrupt firmware must not access an invalid MMIO address");
    check(gpio_oe[0] && gpio_oe[1] && gpio_oe[2], "SDK must configure all IRQ smoke status GPIOs");
    check(gpio_out[1], "C interrupt handler must run from the 0x10 vector");
    check(gpio_out[0], "main firmware must observe handler state after RETIRQ");
    check(!gpio_out[2], "IRQ smoke firmware must not take the failure path");

    $display("PASS: omcu_irq_sdk_tb");
    $finish;
  end
endmodule

`default_nettype wire
