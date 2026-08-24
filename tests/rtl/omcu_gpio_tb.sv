`default_nettype none

module omcu_gpio_tb;
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
  logic [3:0] gpio_in;
  logic [3:0] gpio_out;
  logic [3:0] gpio_oe;
  logic irq;

  always #5 clk = ~clk;

  omcu_gpio #(
    .GPIO_COUNT(4)
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
    .gpio_in_i(gpio_in),
    .gpio_out_o(gpio_out),
    .gpio_oe_o(gpio_oe),
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
    gpio_in = '0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    @(negedge clk);

    mmio_write(32'h0000_0014, 32'h0000_0003);
    check(gpio_oe == 4'b0011, "GPIO output-enable set must affect selected pins");

    mmio_write(32'h0000_0004, 32'h0000_0005);
    check(gpio_out == 4'b0101, "GPIO output set must affect selected pins");

    mmio_write(32'h0000_0008, 32'h0000_0001);
    check(gpio_out == 4'b0100, "GPIO output clear must clear selected pins");

    mmio_write(32'h0000_0024, 32'h0000_0004);
    gpio_in = 4'b0000;
    @(negedge clk);
    gpio_in = 4'b0100;
    @(negedge clk);
    check(irq, "configured rising input edge must assert GPIO interrupt");

    mmio_write(32'h0000_002c, 32'h0000_0004);
    @(negedge clk);
    check(!irq, "GPIO W1C must clear a latched interrupt");

    $display("PASS: omcu_gpio_tb");
    $finish;
  end
endmodule

`default_nettype wire
