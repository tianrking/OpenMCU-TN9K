`default_nettype none
`timescale 1ns / 1ps

module omcu_pulse_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic [31:0] ticks;
  logic [2:0] pulse;
  logic irq;

  always #5 clk = ~clk;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ticks <= 32'h0000_0000;
    else ticks <= ticks + 32'd1;
  end

  omcu_pulse dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .run_ticks_i(ticks), .pulse_i(pulse), .irq_o(irq)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h40000d, offset}; wdata = data; wstrb = 4'hf;
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
      req = 1'b1; write = 1'b1; addr = {24'h40000d, offset}; wdata = data; wstrb = strobe;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b0; addr = {24'h40000d, offset}; #1 data = rdata;
      @(negedge clk);
      req = 1'b0; addr = '0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin if (!condition) begin $error("%s", message); $fatal(1); end end
  endtask

  logic [31:0] status;
  logic [31:0] count;
  logic [31:0] period;
  logic [31:0] last_tick;
  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0; pulse = '0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg_strobe(8'h00, 32'h0000_0003, 4'b0001);
    read_reg(8'h00, status);
    check(status == 32'h0000_0000,
          "PULSE0 control must ignore partial MMIO writes");

    // FILTER=1 needs two consecutive mismatch samples. A one-clock raw pulse
    // may reach the synchronizer, but must not increment the counter.
    write_reg(8'h0c, 32'd1);
    write_reg(8'h04, 32'h0000_0000);
    write_reg(8'h00, 32'h0000_0003);
    pulse[0] = 1'b1;
    @(negedge clk);
    pulse[0] = 1'b0;
    repeat (8) @(negedge clk);
    read_reg(8'h18, count);
    check(count == 32'd0 && !irq,
          "filtered pulse input must reject a short asynchronous-looking glitch");

    // First selected edge establishes the timestamp; second one yields a
    // nonzero period in shared SYSCTRL clock ticks.
    pulse[0] = 1'b1;
    repeat (9) @(negedge clk);
    pulse[0] = 1'b0;
    repeat (9) @(negedge clk);
    pulse[0] = 1'b1;
    repeat (9) @(negedge clk);
    read_reg(8'h10, status);
    read_reg(8'h18, count);
    read_reg(8'h1c, period);
    read_reg(8'h20, last_tick);
    check(status[0] && status[2] && irq,
          "captured pulse must expose pending IRQ and a valid timestamp epoch");
    check(count == 32'd2 && period != 32'h0000_0000 && last_tick != 32'h0000_0000,
          "second selected edge must increment count and calculate period");

    // Stop capture before clear so no legitimate edge can race this reset of
    // the software measurement epoch.
    write_reg(8'h00, 32'h0000_0000);
    write_reg(8'h14, 32'h0000_0001);
    read_reg(8'h10, status);
    read_reg(8'h18, count);
    check(!status[0] && !status[2] && count == 32'd0 && !irq,
          "PULSE CLEAR must reset pending/count/period-valid as one channel epoch");

    // Input selection is an atomic measurement epoch boundary. A pulse on an
    // unselected reviewed pad must not be counted; once GPIO2 is selected the
    // old GPIO0 result is cleared and GPIO2 becomes the only capture source.
    write_reg(8'h04, 32'h0000_0002);
    write_reg(8'h00, 32'h0000_0003);
    pulse[0] = 1'b1;
    repeat (6) @(negedge clk);
    read_reg(8'h18, count);
    check(count == 32'd0,
          "unselected physical input must not affect the compact pulse engine");
    pulse[0] = 1'b0;
    pulse[2] = 1'b1;
    repeat (9) @(negedge clk);
    read_reg(8'h18, count);
    check(count == 32'd1,
          "selected GPIO2 input must start a fresh pulse measurement epoch");

    $display("PASS: omcu_pulse_tb");
    $finish;
  end
endmodule

`default_nettype wire
