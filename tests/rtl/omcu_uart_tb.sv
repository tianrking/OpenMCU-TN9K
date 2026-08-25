`default_nettype none
`timescale 1ns / 1ps

module omcu_uart_tb;
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
  logic rx;
  logic tx;
  logic irq;

  always #5 clk = ~clk;

  omcu_uart #(
    .BAUDDIV_RESET(3)
  ) dut (
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
    .rx_i(rx),
    .tx_o(tx),
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
    end
  endtask

  task automatic mmio_read(input logic [31:0] offset, output logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b0;
      address = offset;
      write_data = '0;
      write_strobe = '0;
      @(negedge clk);
      value = read_data;
      req = 1'b0;
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

  task automatic check_tx_after_one_bit(input logic expected, input string message);
    begin
      repeat (4) @(negedge clk);
      check(tx == expected, message);
    end
  endtask

  task automatic drive_rx_bit(input logic value);
    begin
      rx = value;
      repeat (4) @(negedge clk);
    end
  endtask

  task automatic drive_rx_byte(input logic [7:0] value);
    integer index;
    begin
      rx = 1'b0;
      repeat (4) @(negedge clk);
      for (index = 0; index < 8; index = index + 1) begin
        drive_rx_bit(value[index]);
      end
      drive_rx_bit(1'b1);
      repeat (4) @(negedge clk);
    end
  endtask

  logic [31:0] observed;

  initial begin
    req = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    write_strobe = '0;
    rx = 1'b1;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    // A byte store must not partially enable the UART or make an accidental
    // data/baud configuration visible on the external serial pins.
    mmio_write_strobe(32'h0000_000c, 32'h0000_0007, 4'b0001);
    mmio_read(32'h0000_000c, observed);
    check(observed == 32'h0000_0000,
          "UART control must ignore partial MMIO writes");

    mmio_write(32'h0000_000c, 32'h0000_0007);
    mmio_write(32'h0000_0008, 32'h0000_0003);
    mmio_write(32'h0000_0000, 32'h0000_00a5);
    check(tx == 1'b0, "transmission must start with a low start bit");
    check_tx_after_one_bit(1'b1, "UART data bit 0 must be transmitted LSB first");
    check_tx_after_one_bit(1'b0, "UART data bit 1 must be transmitted");
    check_tx_after_one_bit(1'b1, "UART data bit 2 must be transmitted");
    check_tx_after_one_bit(1'b0, "UART data bit 3 must be transmitted");
    check_tx_after_one_bit(1'b0, "UART data bit 4 must be transmitted");
    check_tx_after_one_bit(1'b1, "UART data bit 5 must be transmitted");
    check_tx_after_one_bit(1'b0, "UART data bit 6 must be transmitted");
    check_tx_after_one_bit(1'b1, "UART data bit 7 must be transmitted");
    check_tx_after_one_bit(1'b1, "UART must transmit a high stop bit");
    repeat (4) @(negedge clk);
    mmio_read(32'h0000_0004, observed);
    check(observed[0], "UART must report TX ready after the stop bit");

    drive_rx_byte(8'h3c);
    repeat (8) @(negedge clk);
    mmio_read(32'h0000_0004, observed);
    check(observed[1], "a received UART byte must become valid");
    check(irq, "received UART data must assert the configured RX interrupt");
    mmio_read(32'h0000_0000, observed);
    check(observed[7:0] == 8'h3c, "UART receive path must preserve all data bits");
    mmio_read(32'h0000_0004, observed);
    check(!observed[1], "reading UART DATA must consume the RX-valid flag");

    $display("PASS: omcu_uart_tb");
    $finish;
  end
endmodule

`default_nettype wire
