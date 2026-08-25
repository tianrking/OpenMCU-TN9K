`default_nettype none
`timescale 1ns / 1ps

module omcu_alarm_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic irq;

  always #5 clk = ~clk;

  omcu_alarm dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .irq_o(irq)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h40000c, offset}; wdata = data; wstrb = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b0; addr = {24'h40000c, offset}; #1 data = rdata;
      @(negedge clk);
      req = 1'b0; addr = '0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin if (!condition) begin $error("%s", message); $fatal(1); end end
  endtask

  logic [31:0] pending;
  logic [31:0] compare0;
  logic [31:0] channel_enable;
  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Channel 0 repeats every three counter ticks, while channel 1 is a
    // one-shot at a different deadline. Both use one shared prescaler/counter.
    write_reg(8'h04, 32'd0);
    write_reg(8'h08, 32'd0);
    write_reg(8'h1c, 32'd2);
    write_reg(8'h20, 32'd4);
    write_reg(8'h2c, 32'd3);
    write_reg(8'h0c, 32'h0000_0003);
    write_reg(8'h10, 32'h0000_0003);
    write_reg(8'h14, 32'h0000_0001);
    write_reg(8'h00, 32'h0000_0001);

    repeat (12) @(negedge clk);
    read_reg(8'h18, pending);
    read_reg(8'h1c, compare0);
    read_reg(8'h0c, channel_enable);
    check((pending & 32'h0000_0003) == 32'h0000_0003 && irq,
          "independent alarm comparisons must set both pending bits and IRQ");
    check(compare0 > 32'd2,
          "periodic channel must advance its own absolute compare deadline");
    check(!channel_enable[1] && channel_enable[0],
          "one-shot must stop only itself while periodic channel remains enabled");

    // Stop time before W1C testing so no legitimate periodic event races it.
    write_reg(8'h00, 32'h0000_0000);
    write_reg(8'h18, 32'h0000_0003);
    read_reg(8'h18, pending);
    check((pending & 32'h0000_0003) == 32'h0000_0000 && !irq,
          "per-channel pending bits must be write-one-to-clear");

    $display("PASS: omcu_alarm_tb");
    $finish;
  end
endmodule

`default_nettype wire
