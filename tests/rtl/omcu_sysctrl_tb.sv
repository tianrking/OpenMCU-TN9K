`default_nettype none

module omcu_sysctrl_tb;
  logic req;
  logic write;
  logic [31:0] address;
  logic ready;
  logic [31:0] read_data;
  logic error;

  omcu_sysctrl #(
    .BUILD_ID(32'h2026_0825),
    .ROM_BYTES(8192),
    .SRAM_BYTES(24576)
  ) dut (
    .req_i(req),
    .write_i(write),
    .addr_i(address),
    .ready_o(ready),
    .read_data_o(read_data),
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

  task automatic check_read(input logic [31:0] offset, input logic [31:0] expected, input string message);
    begin
      address = offset;
      #1;
      check(ready, "SYSCTRL must acknowledge a valid transaction");
      check(!error, "SYSCTRL reads must not report an error");
      check(read_data == expected, message);
    end
  endtask

  initial begin
    req = 1'b1;
    write = 1'b0;
    address = '0;

    check_read(32'h0000_0000, 32'h4f4d_4355, "chip identifier must be OMCU");
    check_read(32'h0000_0004, 32'h0000_0005, "ABI version must encode v0.5");
    check_read(32'h0000_0008, 32'h0000_00ff, "feature bits must include IRQCTRL and every implemented digital peripheral");
    check_read(32'h0000_000c, 32'h2026_0825, "build identifier must be parameterized");
    check_read(32'h0000_0010, 32'h0018_0008, "memory register must report SRAM/ROM KiB");

    $display("PASS: omcu_sysctrl_tb");
    $finish;
  end
endmodule

`default_nettype wire
