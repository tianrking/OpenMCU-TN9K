`default_nettype none
`timescale 1ns / 1ps

module omcu_pwm_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic pwm;

  always #5 clk = ~clk;

  omcu_pwm dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .pwm_o(pwm)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk); req = 1'b1; write = 1'b1; addr = {24'h400006, offset}; wdata = data; wstrb = 4'hf;
      @(negedge clk); req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin if (!condition) begin $error("%s", message); $fatal(1); end end
  endtask

  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0;
    repeat (3) @(negedge clk); rst_n = 1'b1;
    write_reg(8'h04, 32'd0);
    write_reg(8'h08, 32'd3);
    write_reg(8'h0c, 32'd2);
    write_reg(8'h00, 32'd1);

    // The write that enables PWM creates the first count-zero high phase.
    // These following samples cover count one, two, three, then the rollover
    // back to count zero: high, low, low, high.
    @(negedge clk); check(pwm, "PWM must remain high for count one");
    @(negedge clk); check(!pwm, "PWM must be low for count two");
    @(negedge clk); check(!pwm, "PWM must be low for count three");
    @(negedge clk); check(pwm, "PWM must wrap to high at period rollover");

    write_reg(8'h00, 32'd3);
    #1 check(pwm == !dut.active_level, "PWM invert must invert the active waveform");
    $display("PASS: omcu_pwm_tb");
    $finish;
  end
endmodule

`default_nettype wire
