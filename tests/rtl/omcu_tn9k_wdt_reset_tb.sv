`default_nettype none
`timescale 1ns / 1ps

// Checks the real board wrapper path: compiled firmware -> WDT0 -> reset
// request -> Tang reset release shift register -> whole SoC reset.
module omcu_tn9k_wdt_reset_tb;
  logic clk = 1'b0;
  logic resetn = 1'b0;
  logic uart_tx;
  logic [5:0] led_n;
  logic watchdog_request_seen = 1'b0;

  always #5 clk = ~clk;
  always @(posedge clk) begin
    if (dut.watchdog_reset_request) watchdog_request_seen <= 1'b1;
  end

  omcu_tn9k_bringup_top #(
    .ROM_INIT_FILE("build/sdk/omcu_wdt_reset_smoke.hex")
  ) dut (
    .clk_27m_i(clk),
    .resetn_i(resetn),
    .uart_rx_i(1'b1),
    .uart_tx_o(uart_tx),
    .led_n_o(led_n)
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
    resetn = 1'b1;
    wait (dut.sys_rst_ni === 1'b1);
    wait (dut.sys_rst_ni === 1'b0);
    check(watchdog_request_seen,
          "watchdog expiry must be the cause of the Tang reset assertion");
    repeat (4) @(negedge clk);
    check(dut.sys_rst_ni === 1'b1,
          "Tang reset release logic must restart the SoC after watchdog expiry");
    check(!dut.cpu_trap, "watchdog-reset firmware must not trap before reset");

    $display("PASS: omcu_tn9k_wdt_reset_tb");
    $finish;
  end
endmodule

`default_nettype wire
