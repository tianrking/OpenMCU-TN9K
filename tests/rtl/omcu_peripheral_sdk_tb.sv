`default_nettype none
`timescale 1ns / 1ps

// End-to-end SDK smoke test for the v0.4 digital peripheral set. The C
// application checks SYSCTRL features, configures PWM/WDT, performs a real SPI
// transaction and signals its result through GPIO.
module omcu_peripheral_sdk_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [3:0] gpio_out;
  logic [3:0] gpio_oe;
  logic spi_mosi;
  logic spi_sck;
  logic spi_cs_n;
  logic pwm;
  logic wdt_reset_req;
  logic cpu_trap;
  logic bus_error;
  logic bus_error_seen = 1'b0;
  logic wdt_reset_seen = 1'b0;
  logic pwm_high_seen = 1'b0;
  logic [7:0] spi_capture = 8'h00;
  integer spi_bit_count = 0;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (bus_error) bus_error_seen <= 1'b1;
    if (wdt_reset_req) wdt_reset_seen <= 1'b1;
    if (pwm) pwm_high_seen <= 1'b1;
  end

  always @(negedge spi_cs_n) begin
    spi_capture = 8'h00;
    spi_bit_count = 0;
  end

  always @(posedge spi_sck) begin
    if (!spi_cs_n) begin
      spi_capture = {spi_capture[6:0], spi_mosi};
      spi_bit_count = spi_bit_count + 1;
    end
  end

  omcu_picorv32_system #(
    .GPIO_COUNT(4),
    // Match sdk/linker/omcu_fpga_bringup.ld and the Tang production wrapper.
    .ROM_WORDS(2048),
    .SRAM_BYTES(45056),
    .ROM_INIT_FILE("build/sdk/omcu_peripheral_smoke.hex")
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
    .spi_mosi_o(spi_mosi),
    .spi_sck_o(spi_sck),
    .spi_cs_n_o(spi_cs_n),
    .spi_irq_o(),
    .wdt_irq_o(),
    .wdt_reset_req_o(wdt_reset_req),
    .pwm_o(pwm),
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
    repeat (2000) @(negedge clk);

    check(!cpu_trap, "compiled peripheral SDK firmware must not trap");
    check(!bus_error_seen, "compiled peripheral SDK firmware must not hit an invalid address");
    check(!wdt_reset_seen, "fed long-timeout watchdog must not request reset");
    check(gpio_oe[0] && gpio_oe[1], "peripheral SDK firmware must configure pass/fail GPIO");
    check(gpio_out[0] && !gpio_out[1], "peripheral SDK firmware must report success");
    check(spi_bit_count == 8 && spi_capture == 8'ha5,
          "SDK SPI helper must execute the expected byte transfer");
    check(pwm_high_seen, "SDK PWM helper must drive an active PWM phase");

    $display("PASS: omcu_peripheral_sdk_tb");
    $finish;
  end
endmodule

`default_nettype wire
