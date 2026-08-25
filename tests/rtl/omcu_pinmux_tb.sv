`default_nettype none
`timescale 1ns / 1ps

module omcu_pinmux_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic uart1_enable;
  logic pwm1_enable;
  logic timer1_enable;
  logic pulse0_enable;

  always #5 clk = ~clk;

  omcu_pinmux dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(),
    .read_data_o(rdata), .error_o(), .uart1_enable_o(uart1_enable),
    .pwm1_enable_o(pwm1_enable), .timer1_enable_o(timer1_enable),
    .pulse0_enable_o(pulse0_enable)
  );

  task automatic write_ctrl(input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = 32'h4000_b000;
      wdata = value; wstrb = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
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

  initial begin
    req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    check(!uart1_enable && !pwm1_enable && !timer1_enable && !pulse0_enable,
          "GPIO must own all alternate-function pads after reset");
    write_ctrl(32'h0000_0001);
    check(uart1_enable && !pwm1_enable && !timer1_enable,
          "PINMUX CTRL bit0 must select UART1 only");
    write_ctrl(32'h0000_0006);
    check(!uart1_enable && pwm1_enable && timer1_enable && !pulse0_enable,
          "PINMUX CTRL must independently select later PWM1/TIMER1 groups");
    write_ctrl(32'h0000_0008);
    check(!uart1_enable && !pwm1_enable && !timer1_enable && pulse0_enable,
          "PINMUX CTRL bit3 must independently select PULSE0 input ownership");
    $display("PASS: omcu_pinmux_tb");
    $finish;
  end
endmodule

`default_nettype wire
