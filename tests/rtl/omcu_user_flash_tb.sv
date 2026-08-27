`default_nettype none
`timescale 1ns / 1ps

module omcu_user_flash_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic ready;
  logic [31:0] rdata;
  logic error;
  logic timebase_reset;
  logic [16:0] timebase_count;
  logic product_req;
  logic product_write;
  logic [31:0] product_addr;
  logic [31:0] product_wdata;
  logic [3:0] product_wstrb;
  logic product_ready;
  logic product_timebase_reset;
  logic [16:0] product_timebase_count;
  logic [4:0] product_tick_divider;
  wire product_tick = product_tick_divider == 5'd26;

  always #5 clk = ~clk;

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n || timebase_reset) begin
      timebase_count <= '0;
    end else begin
      timebase_count <= timebase_count + 1'b1;
    end
  end

  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) begin
      product_tick_divider <= '0;
      product_timebase_count <= '0;
    end else if (product_timebase_reset) begin
      product_tick_divider <= '0;
      product_timebase_count <= '0;
    end else if (product_tick) begin
      product_tick_divider <= '0;
      product_timebase_count <= product_timebase_count + 1'b1;
    end else begin
      product_tick_divider <= product_tick_divider + 1'b1;
    end
  end

  // Driving the timebase every cycle makes one simulation cycle equal to one
  // microsecond of controller time.
  omcu_user_flash #(
    .FLASH_BYTES(4096),
    .CLOCK_HZ(100000),
    .PRESENT(1)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .timebase_tick_i(1'b1),
    .timebase_count_i(timebase_count),
    .req_i(req),
    .write_i(write),
    .addr_i(addr),
    .write_data_i(wdata),
    .write_strobe_i(wstrb),
    .ready_o(ready),
    .read_data_o(rdata),
    .error_o(error)
  );

  // Keep a product-clock instance in the regression. Its erase need not run
  // to completion; checking that it remains busy catches 32-bit constant
  // arithmetic overflow without adding millions of simulation cycles.
  omcu_user_flash #(
    .FLASH_BYTES(4096),
    .CLOCK_HZ(27000000),
    .PRESENT(1)
  ) product_timing_dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .timebase_tick_i(product_tick),
    .timebase_count_i(product_timebase_count),
    .req_i(product_req),
    .write_i(product_write),
    .addr_i(product_addr),
    .write_data_i(product_wdata),
    .write_strobe_i(product_wstrb),
    .ready_o(product_ready),
    .read_data_o(),
    .error_o()
  );

  integer last_wait_cycles;

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic transact(
    input logic transaction_write,
    input logic [31:0] transaction_addr,
    input logic [31:0] transaction_data,
    input logic [3:0] transaction_strobe,
    output logic [31:0] response_data,
    output logic response_error
  );
    integer wait_cycles;
    begin
      if (transaction_write) begin
        @(negedge clk);
        timebase_reset = 1'b1;
        @(negedge clk);
        timebase_reset = 1'b0;
      end
      @(negedge clk);
      req = 1'b1;
      write = transaction_write;
      addr = transaction_addr;
      wdata = transaction_data;
      wstrb = transaction_strobe;

      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
      addr = 32'h0000_0000;
      wdata = 32'h0000_0000;
      wstrb = 4'b0000;

      wait_cycles = 0;
      while (!ready) begin
        @(posedge clk);
        wait_cycles = wait_cycles + 1;
        check(wait_cycles < 150000, "user-flash transaction timed out");
      end
      response_data = rdata;
      response_error = error;
      last_wait_cycles = wait_cycles;
      @(posedge clk);
    end
  endtask

  logic [31:0] response;
  logic response_error;

  initial begin
    req = 1'b0;
    write = 1'b0;
    addr = 32'h0000_0000;
    wdata = 32'h0000_0000;
    wstrb = 4'b0000;
    timebase_reset = 1'b0;
    product_req = 1'b0;
    product_write = 1'b0;
    product_addr = 32'h0000_0000;
    product_wdata = 32'h0000_0000;
    product_wstrb = 4'b0000;
    product_timebase_reset = 1'b0;
    last_wait_cycles = 0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    transact(1'b0, 32'h0000_0040, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(!response_error, "erased user flash must be readable");
    check(response == 32'h0000_0000, "erased user flash must read as all zeros");

    transact(1'b1, 32'h0000_0040, 32'ha5a5_0f0f, 4'b1111,
             response, response_error);
    check(!response_error, "aligned word program must succeed");
    transact(1'b0, 32'h0000_0040, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(response == 32'ha5a5_0f0f, "programmed word must be readable");

    transact(1'b1, 32'h0000_0040, 32'hffff_ffff, 4'b1111,
             response, response_error);
    check(!response_error, "a second aligned program command must complete");
    transact(1'b0, 32'h0000_0040, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(response == 32'hffff_ffff,
          "programming must only add one bits until the next page erase");

    transact(1'b1, 32'h0000_0043, 32'h0000_0000, 4'b0001,
             response, response_error);
    check(!response_error, "an 8-bit command must erase its 2 KiB page");
    check(last_wait_cycles >= 120040,
          "page erase must retain its complete 120000-tick phase sequence");
    transact(1'b0, 32'h0000_0040, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(response == 32'h0000_0000, "page erase must restore all zeros");

    transact(1'b1, 32'h0000_0040, 32'h0000_0000, 4'b0011,
             response, response_error);
    check(response_error, "partial program writes must be rejected");
    transact(1'b0, 32'h0000_1000, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(response_error, "addresses outside the user-flash window must fail");

    @(negedge clk);
    product_timebase_reset = 1'b1;
    @(negedge clk);
    product_timebase_reset = 1'b0;
    @(negedge clk);
    product_req = 1'b1;
    product_write = 1'b1;
    product_wstrb = 4'b0001;
    @(negedge clk);
    product_req = 1'b0;
    product_write = 1'b0;
    product_wstrb = 4'b0000;
    repeat (100) begin
      @(posedge clk);
      check(!product_ready,
            "27 MHz page erase must not finish in the first 100 cycles");
    end

    $display("PASS: omcu_user_flash_tb");
    $finish;
  end
endmodule

`default_nettype wire
