`default_nettype none
`timescale 1ns / 1ps

// Verifies the 27 MHz reset-release and active-low LED board adapter. This is
// still a digital simulation; it cannot validate pin assignment or LED wiring.
module omcu_tn9k_bringup_top_tb;
  logic clk_27m = 1'b0;
  logic resetn = 1'b0;
  logic uart_rx = 1'b1;
  logic uart_tx;
  logic [5:0] led_n;

  always #18.518 clk_27m = ~clk_27m;

  omcu_tn9k_bringup_top dut (
    .clk_27m_i(clk_27m),
    .resetn_i(resetn),
    .uart_rx_i(uart_rx),
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
    repeat (4) @(negedge clk_27m);
    resetn = 1'b1;

    repeat (90) @(negedge clk_27m);
    check(led_n == 6'b111110,
          "the board adapter must turn on only active-low LED0 after firmware bring-up");

    $display("PASS: omcu_tn9k_bringup_top_tb");
    $finish;
  end
endmodule

`default_nettype wire
