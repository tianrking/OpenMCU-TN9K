`default_nettype none
`timescale 1ns / 1ps

module omcu_pwm1_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic [3:0] pwm;

  always #5 clk = ~clk;

  omcu_pwm1 dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .pwm_o(pwm)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h40000a, offset};
      wdata = data; wstrb = 4'hf;
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

    check(pwm == 4'b0000, "PWM1 reset output must be low on every channel");
    // Disabled output stays low even if future software has left invert bits.
    write_reg(8'h00, 32'h0000_00f0);
    check(pwm == 4'b0000,
          "disabled PWM1 with all invert bits set must still be safely low");

    write_reg(8'h04, 32'd0);
    write_reg(8'h08, 32'd3);
    write_reg(8'h0c, 32'd1);
    write_reg(8'h10, 32'd2);
    write_reg(8'h14, 32'd3);
    write_reg(8'h18, 32'd4);
    write_reg(8'h00, 32'h0000_0001);

    // At count zero every configured duty is active.  Subsequent shared
    // counter values 1, 2, 3 prove the four channels retain a common phase.
    check(pwm == 4'b1111, "PWM1 count zero must start every nonzero duty high");
    @(negedge clk);
    check(pwm == 4'b1110, "PWM1 count one must end channel 0 only");
    @(negedge clk);
    check(pwm == 4'b1100, "PWM1 count two must end channels 0 and 1");
    @(negedge clk);
    check(pwm == 4'b1000, "PWM1 count three must leave only duty-four channel high");
    @(negedge clk);
    check(pwm == 4'b1111, "PWM1 must wrap all four channels together");

    write_reg(8'h00, 32'h0000_0011);
    #1 check(pwm[0] == !dut.active_level[0],
             "PWM1 CTRL.INVERT0 must invert only channel 0's active waveform");
    write_reg(8'h00, 32'h0000_0010);
    check(pwm == 4'b0000,
          "disabling PWM1 must force every channel low regardless of inversion");

    $display("PASS: omcu_pwm1_tb");
    $finish;
  end
endmodule

`default_nettype wire
