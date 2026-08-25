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
  logic [15:0] timebase_count;
  logic [15:0] timebase_prescale;
  logic timebase_enable;
  logic timebase_tick;

  always #5 clk = ~clk;
  // A minimal TIMER0 model: its count and tick are owned outside ALARM0.
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      timebase_count <= 16'h0000;
      timebase_tick <= 1'b0;
    end else begin
      timebase_tick <= timebase_enable;
      if (timebase_enable) begin
        timebase_count <= timebase_count + 16'd1;
      end
    end
  end

  omcu_alarm dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .timebase_count_i(timebase_count),
    .timebase_prescale_i(timebase_prescale), .timebase_enable_i(timebase_enable),
    .timebase_tick_i(timebase_tick), .irq_o(irq)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h40000c, offset}; wdata = data; wstrb = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic write_reg_strobe(
    input logic [7:0] offset,
    input logic [31:0] data,
    input logic [3:0] strobe
  );
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h40000c, offset}; wdata = data; wstrb = strobe;
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
  logic [31:0] count_mirror;
  logic [15:0] deadline0;
  logic [15:0] deadline1;
  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0;
    timebase_prescale = 16'd3;
    timebase_enable = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg_strobe(8'h00, 32'h0000_0001, 4'b0001);
    read_reg(8'h00, channel_enable);
    check(channel_enable == 32'h0000_0000,
          "ALARM0 control must ignore partial MMIO writes");
    @(negedge clk);
    timebase_enable = 1'b1;

    // PRESCALE and COUNT are read-only TIMER0 mirrors. ALARM0 must not own a
    // second counter just to provide independent deadline comparisons.
    repeat (2) @(negedge clk);
    read_reg(8'h04, compare0);
    read_reg(8'h08, count_mirror);
    check(compare0 == 32'd3 && count_mirror != 32'h0000_0000,
          "ALARM0 must mirror the TIMER0 prescale and low 16-bit count");

    // Channel 0 repeats every 32 shared TIMER0 ticks, while channel 1 is a
    // one-shot at a different deadline. Both comparators remain parallel.
    deadline0 = timebase_count + 16'd64;
    deadline1 = timebase_count + 16'd96;
    write_reg(8'h1c, {16'h0000, deadline0});
    write_reg(8'h20, {16'h0000, deadline1});
    write_reg(8'h2c, 32'd32);
    write_reg(8'h0c, 32'h0000_0003);
    write_reg(8'h10, 32'h0000_0003);
    write_reg(8'h14, 32'h0000_0001);
    write_reg(8'h00, 32'h0000_0001);

    repeat (180) @(negedge clk);
    read_reg(8'h18, pending);
    read_reg(8'h1c, compare0);
    read_reg(8'h0c, channel_enable);
    check((pending & 32'h0000_0003) == 32'h0000_0003 && irq,
          "independent TIMER0-based alarm comparisons must set both pending bits and IRQ");
    check(compare0 > {16'h0000, deadline0},
          "periodic channel must advance its own modular compare deadline");
    check(!channel_enable[1] && channel_enable[0],
          "one-shot must stop only itself while periodic channel remains enabled");

    // Stop ALARM0 comparisons before W1C testing. TIMER0 intentionally keeps
    // running, proving the ALARM gate does not own or disturb its timebase.
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
