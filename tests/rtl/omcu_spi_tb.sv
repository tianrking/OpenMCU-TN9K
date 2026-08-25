`default_nettype none
`timescale 1ns / 1ps

module omcu_spi_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic miso = 1'b1;
  logic mosi;
  logic sck;
  logic cs_n;
  logic irq;
  logic [7:0] mosi_capture = 8'h00;
  integer mosi_count = 0;
  integer miso_index = 7;
  localparam logic [7:0] RX_EXPECTED = 8'h3c;

  always #5 clk = ~clk;

  omcu_spi dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_i(req),
    .write_i(write),
    .addr_i(addr),
    .write_data_i(wdata),
    .write_strobe_i(wstrb),
    .ready_o(),
    .read_data_o(rdata),
    .error_o(),
    .miso_i(miso),
    .mosi_o(mosi),
    .sck_o(sck),
    .cs_n_o(cs_n),
    .irq_o(irq)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      addr = {24'h400003, offset};
      wdata = data;
      wstrb = 4'hf;
      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
      addr = '0;
      wdata = '0;
      wstrb = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b0;
      addr = {24'h400003, offset};
      #1 data = rdata;
      @(negedge clk);
      req = 1'b0;
      addr = '0;
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

  always @(negedge cs_n) begin
    miso_index = 7;
    miso = RX_EXPECTED[miso_index];
    mosi_capture = 8'h00;
    mosi_count = 0;
  end

  always @(posedge sck) begin
    if (!cs_n) begin
      mosi_capture = {mosi_capture[6:0], mosi};
      mosi_count = mosi_count + 1;
    end
  end

  always @(negedge sck) begin
    if (!cs_n && miso_index > 0) begin
      miso_index = miso_index - 1;
      miso = RX_EXPECTED[miso_index];
    end
  end

  logic [31:0] status;
  logic [31:0] received;

  initial begin
    req = 1'b0;
    write = 1'b0;
    addr = '0;
    wdata = '0;
    wstrb = '0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg(8'h08, 32'd1);       // Two system clocks per SCK half period.
    write_reg(8'h0c, 32'h00000003); // Enable and enable DONE interrupt.
    write_reg(8'h00, 32'h000000a5);
    write_reg(8'h10, 32'h00000001);

    repeat (80) @(negedge clk);
    read_reg(8'h04, status);
    read_reg(8'h00, received);
    check(!status[0], "SPI must leave BUSY after an eight-bit transfer");
    check(status[1], "SPI must set DONE at transfer completion");
    check(irq, "SPI DONE must assert the enabled interrupt output");
    check(received[7:0] == RX_EXPECTED, "SPI must sample MISO MSB first");
    check(mosi_count == 8, "SPI must generate exactly eight sampling edges");
    check(mosi_capture == 8'ha5, "SPI must emit TX data MSB first");
    check(cs_n, "SPI chip select must release after the automatic byte transfer");

    write_reg(8'h04, 32'h00000002);
    read_reg(8'h04, status);
    check(!status[1] && !irq, "SPI DONE must be write-one-to-clear");

    // ABI 0.6 CSHOLD keeps the physical CS assertion across separate byte
    // START operations.  This is required by real framed SPI devices such as
    // W5500, ADCs and DACs; the legacy one-byte transfer above remains valid.
    write_reg(8'h0c, 32'h00000007);
    write_reg(8'h00, 32'h00000012);
    write_reg(8'h10, 32'h00000001);
    repeat (80) @(negedge clk);
    read_reg(8'h04, status);
    check(!status[0] && status[5],
          "CSHOLD must leave CS asserted after its first completed byte");
    write_reg(8'h00, 32'h00000034);
    write_reg(8'h10, 32'h00000001);
    repeat (80) @(negedge clk);
    check(cs_n == 1'b0,
          "CSHOLD must not deassert CS between sequential byte transfers");
    check(mosi_count == 16 && mosi_capture == 8'h34,
          "CSHOLD must clock both byte transfers under one CS assertion");
    write_reg(8'h0c, 32'h00000003);
    @(negedge clk);
    check(cs_n == 1'b1,
          "clearing CSHOLD after BUSY releases the framed SPI transaction");

    $display("PASS: omcu_spi_tb");
    $finish;
  end
endmodule

`default_nettype wire
