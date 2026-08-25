`default_nettype none
`timescale 1ns / 1ps

module omcu_wdt_tb;
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
  logic reset_seen = 1'b0;

  always #5 clk = ~clk;
  always @(posedge clk) if (reset_req) reset_seen <= 1'b1;

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

  task automatic write_reg_strobe(
    input logic [7:0] offset,
    input logic [31:0] data,
    input logic [3:0] strobe
  );
    begin
      @(negedge clk); req = 1'b1; write = 1'b1; addr = {24'h400005, offset}; wdata = data; wstrb = strobe;
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
  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0;
    repeat (3) @(negedge clk); rst_n = 1'b1;

    write_reg_strobe(8'h00, 32'h00000007, 4'b0001);
    check(!dut.enable_q,
          "WDT partial MMIO writes must not arm a partially configured supervisor");

    write_reg(8'h04, 32'd3);
    write_reg(8'h00, 32'h00000007); // enable, reset request, IRQ
    repeat (2) @(negedge clk);
    write_reg(8'h08, 32'h51f15eed);
    repeat (7) @(negedge clk);
    read_reg(8'h0c, status);
    check(status[0], "watchdog expiry must latch STATUS.EXPIRED");
    check(irq, "watchdog expiry must assert an enabled IRQ");
    check(reset_seen, "watchdog expiry must emit a reset request pulse");

    // Stop the deliberately tiny test timeout before checking W1C so a new
    // expiry cannot legitimately race the clear transaction.
    write_reg(8'h00, 32'h00000000);
    write_reg(8'h0c, 32'h00000001);
    read_reg(8'h0c, status);
    check(!status[0] && !irq, "watchdog EXPIRED must be write-one-to-clear");
    $display("PASS: omcu_wdt_tb");
    $finish;
  end
endmodule

`default_nettype wire
