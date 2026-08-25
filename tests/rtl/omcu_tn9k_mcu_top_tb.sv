`default_nettype none
`timescale 1ns / 1ps

// Product-top smoke test. FLASH608K is supplied by the simulation-only stub
// in gowin_flash608k_stub.sv; real FPGA builds use the Gowin primitive.
module omcu_tn9k_mcu_top_tb;
  logic clk_27m = 1'b0;
  logic resetn = 1'b0;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [5:0] led_n;
  logic spi_miso = 1'b1;
  logic spi_mosi;
  logic spi_sck;
  logic spi_cs_n;
  logic pwm0;
  tri1 i2c_scl;
  tri1 i2c_sda;
  tri1 [11:0] gpio;
  logic saw_physical_flash_access = 1'b0;
  logic saw_bus_error = 1'b0;
  logic saw_boot_request_ack = 1'b0;

  always #18.518 clk_27m = ~clk_27m;

  omcu_tn9k_mcu_top dut (
    .clk_27m_i(clk_27m),
    .resetn_i(resetn),
    .uart_rx_i(uart_rx),
    .uart_tx_o(uart_tx),
    .led_n_o(led_n),
    .spi0_miso_i(spi_miso),
    .spi0_mosi_o(spi_mosi),
    .spi0_sck_o(spi_sck),
    .spi0_cs_n_o(spi_cs_n),
    .i2c0_scl_io(i2c_scl),
    .i2c0_sda_io(i2c_sda),
    .pwm0_o(pwm0),
    .gpio_io(gpio)
  );

  always @(posedge clk_27m) begin
    if (dut.platform.system.user_flash.flash_xe) begin
      saw_physical_flash_access <= 1'b1;
    end
    if (dut.platform.bus_error) begin
      saw_bus_error <= 1'b1;
    end
    if (dut.platform.system.mmio.sysctrl.boot_request_ack_o) begin
      saw_boot_request_ack <= 1'b1;
    end
  end

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  initial begin
    repeat (4) @(negedge clk_27m);
    resetn = 1'b1;

    // Model the retained request produced by a running application.  The
    // immutable checked-in Boot ROM must consume it by issuing SYSCTRL's ACK
    // command before it enters its UART session.  Force is released on that
    // actual MMIO pulse; the request-production/reset path is covered by the
    // separate compiled-firmware Tang wrapper test.
    force dut.platform.boot_request_pending_q = 1'b1;
    fork
      begin
        wait (dut.platform.system.mmio.sysctrl.boot_request_ack_o == 1'b1);
        release dut.platform.boot_request_pending_q;
      end
    join_none

    // Two all-erased slot headers are scanned before the loader settles in
    // its UART wait loop. This proves the product wrapper selected the
    // physical FLASH608K branch, without claiming hardware flash behavior.
    repeat (12000) @(negedge clk_27m);
    check(saw_physical_flash_access,
          "product MCU top must access the FLASH608K primitive during boot scan");
    check(dut.platform.system.mmio.sysctrl.boot_ctrl_read[1],
          "product MCU top must advertise the retained Bootloader request path");
    check(!saw_bus_error,
          "erased User Flash header scans must stay inside the mapped window");
    check(led_n == 6'b111111,
          "bootloader must leave all active-low LEDs off before an app runs");
    check(!dut.platform.cpu_trap,
          "checked-in bootloader image must not trap during initial header scan");
    check(saw_boot_request_ack,
          "checked-in Boot ROM must acknowledge a retained software boot request");

    $display("PASS: omcu_tn9k_mcu_top_tb");
    $finish;
  end
endmodule

`default_nettype wire
