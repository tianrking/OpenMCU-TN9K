`default_nettype none

// Initial directed smoke test. It is intentionally simulator-neutral; the
// project's eventual runner may be iverilog, Verilator or cocotb.
module omcu_timer_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] address;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic ready;
  logic [31:0] read_data;
  logic error;
  logic irq;

  always #5 clk = ~clk;

  omcu_timer dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_i(req),
    .write_i(write),
    .addr_i(address),
    .write_data_i(write_data),
    .write_strobe_i(write_strobe),
    .ready_o(ready),
    .read_data_o(read_data),
    .error_o(error),
    .irq_o(irq)
  );

  task automatic mmio_write(input logic [31:0] offset, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      address = offset;
      write_data = value;
      write_strobe = 4'hf;
      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
    end
  endtask

  task automatic mmio_write_strobe(
    input logic [31:0] offset,
    input logic [31:0] value,
    input logic [3:0] strobe
  );
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      address = offset;
      write_data = value;
      write_strobe = strobe;
      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
      write_strobe = '0;
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
    req = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    write_strobe = '0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    mmio_write_strobe(32'h0000_0000, 32'h0000_0007, 4'b0001);
    check(!dut.enable_q,
          "TIMER0 partial MMIO writes must not create a torn configuration");

    // Compare at count 2 with a no-divider periodic timer.
    mmio_write(32'h0000_0004, 32'h0000_0000);
    mmio_write(32'h0000_0008, 32'h0000_0000);
    mmio_write(32'h0000_000c, 32'h0000_0002);
    mmio_write(32'h0000_0000, 32'h0000_0007);

    repeat (5) @(negedge clk);
    check(irq, "timer should assert its enabled compare interrupt");

    mmio_write(32'h0000_0010, 32'h0000_0001);
    @(negedge clk);
    check(!irq, "write-one-to-clear should clear timer interrupt");

    $display("PASS: omcu_timer_tb");
    $finish;
  end
endmodule

`default_nettype wire
