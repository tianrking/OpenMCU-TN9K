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

  always #5 clk = ~clk;

  // A low nominal clock makes the behavioural erase wait short without
  // changing the controller's clock-count timing contract.
  omcu_user_flash #(
    .FLASH_BYTES(4096),
    .CLOCK_HZ(100000),
    .PRESENT(1)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_i(req),
    .write_i(write),
    .addr_i(addr),
    .write_data_i(wdata),
    .write_strobe_i(wstrb),
    .ready_o(ready),
    .read_data_o(rdata),
    .error_o(error)
  );

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
        check(wait_cycles < 20000, "user-flash transaction timed out");
      end
      response_data = rdata;
      response_error = error;
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

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    transact(1'b0, 32'h0000_0040, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(!response_error, "erased user flash must be readable");
    check(response == 32'hffff_ffff, "erased user flash must read as all ones");

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
    check(response == 32'ha5a5_0f0f,
          "programming must never change a user-flash zero back to one");

    transact(1'b1, 32'h0000_0043, 32'h0000_0000, 4'b0001,
             response, response_error);
    check(!response_error, "an 8-bit command must erase its 2 KiB page");
    transact(1'b0, 32'h0000_0040, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(response == 32'hffff_ffff, "page erase must restore all ones");

    transact(1'b1, 32'h0000_0040, 32'h0000_0000, 4'b0011,
             response, response_error);
    check(response_error, "partial program writes must be rejected");
    transact(1'b0, 32'h0000_1000, 32'h0000_0000, 4'b0000,
             response, response_error);
    check(response_error, "addresses outside the user-flash window must fail");

    $display("PASS: omcu_user_flash_tb");
    $finish;
  end
endmodule

`default_nettype wire
