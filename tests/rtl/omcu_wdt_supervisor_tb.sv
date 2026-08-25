`default_nettype none
`timescale 1ns / 1ps

module omcu_wdt_supervisor_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic irq;
  logic reset_req;
  integer reset_pulses = 0;

  always #5 clk = ~clk;
  always @(posedge clk) if (reset_req) reset_pulses <= reset_pulses + 1;

  omcu_wdt dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .irq_o(irq), .reset_req_o(reset_req)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk); req = 1'b1; write = 1'b1; addr = {24'h400005, offset}; wdata = data; wstrb = 4'hf;
      @(negedge clk); req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] data);
    begin
      @(negedge clk); req = 1'b1; write = 1'b0; addr = {24'h400005, offset}; #1 data = rdata;
      @(negedge clk); req = 1'b0; addr = '0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin if (!condition) begin $error("%s", message); $fatal(1); end end
  endtask

  logic [31:0] status;
  logic [31:0] seen;
  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // Pretimeout is an independent warning stage, then a feed without all
    // required software heartbeats becomes a recorded watchdog failure.
    write_reg(8'h04, 32'd20);
    write_reg(8'h10, 32'd3);
    write_reg(8'h14, 32'd0);
    write_reg(8'h18, 32'h0000_0003);
    write_reg(8'h00, 32'h0000_002f);
    repeat (5) @(negedge clk);
    read_reg(8'h0c, status);
    check(status[2] && irq,
          "enabled pretimeout must raise a warning status and IRQ before expiry");
    write_reg(8'h08, 32'h51f1_5eed);
    repeat (2) @(negedge clk);
    read_reg(8'h0c, status);
    check(status[0] && status[4] && status[5] && reset_pulses > 0,
          "missing required heartbeat must reject feed, record failure and request reset");

    // A feed inside the configured minimum window is a different diagnosable
    // fault and must not be silently accepted merely because no heartbeats are
    // required.
    write_reg(8'h00, 32'h0000_0000);
    write_reg(8'h0c, 32'h0000_003d);
    write_reg(8'h04, 32'd20);
    write_reg(8'h10, 32'd0);
    write_reg(8'h14, 32'd10);
    write_reg(8'h18, 32'h0000_0000);
    write_reg(8'h00, 32'h0000_0017);
    write_reg(8'h08, 32'h51f1_5eed);
    repeat (2) @(negedge clk);
    read_reg(8'h0c, status);
    check(status[0] && status[3] && status[5],
          "early feed must set WINDOW_VIOLATION plus normal watchdog failure status");

    // A fresh epoch with both heartbeat bits seen after the window opens must
    // accept the feed, clear the heartbeat epoch and leave failure flags low.
    write_reg(8'h00, 32'h0000_0000);
    write_reg(8'h0c, 32'h0000_003d);
    write_reg(8'h04, 32'd20);
    write_reg(8'h14, 32'd2);
    write_reg(8'h18, 32'h0000_0003);
    write_reg(8'h00, 32'h0000_0035);
    repeat (4) @(negedge clk);
    write_reg(8'h20, 32'h0000_0001);
    write_reg(8'h20, 32'h0000_0002);
    read_reg(8'h1c, seen);
    check((seen & 32'h0000_0003) == 32'h0000_0003,
          "heartbeat kick register must accumulate independent task bits");
    write_reg(8'h08, 32'h51f1_5eed);
    @(negedge clk);
    read_reg(8'h0c, status);
    read_reg(8'h1c, seen);
    check((status & 32'h0000_003d) == 32'h0000_0000 && seen == 32'h0000_0000,
          "valid windowed multi-heartbeat feed must restart a clean watchdog epoch");

    $display("PASS: omcu_wdt_supervisor_tb");
    $finish;
  end
endmodule

`default_nettype wire
