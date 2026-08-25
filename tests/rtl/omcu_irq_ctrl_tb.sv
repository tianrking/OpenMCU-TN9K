`default_nettype none
`timescale 1ns / 1ps

module omcu_irq_ctrl_tb;
  localparam logic [31:0] IRQ_GPIO0  = 32'h0000_0100;
  localparam logic [31:0] IRQ_UART0  = 32'h0000_0200;
  localparam logic [31:0] IRQ_TIMER0 = 32'h0000_0400;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] write_data;
  logic [3:0] write_strobe;
  logic [31:0] read_data;
  logic [5:0] sources;
  logic [31:0] irq_vector;

  always #5 clk = ~clk;

  omcu_irq_ctrl #(
    .SOURCE_COUNT(6),
    .IRQ_BASE(8)
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .req_i(req),
    .write_i(write),
    .addr_i(addr),
    .write_data_i(write_data),
    .write_strobe_i(write_strobe),
    .ready_o(),
    .read_data_o(read_data),
    .error_o(),
    .source_i(sources),
    .irq_o(irq_vector)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      addr = 32'h4000_7000 + offset;
      write_data = value;
      write_strobe = 4'hf;
      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
      addr = '0;
      write_data = '0;
      write_strobe = '0;
    end
  endtask

  task automatic write_reg_strobe(
    input logic [7:0] offset,
    input logic [31:0] value,
    input logic [3:0] strobe
  );
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      addr = 32'h4000_7000 + offset;
      write_data = value;
      write_strobe = strobe;
      @(negedge clk);
      req = 1'b0;
      write = 1'b0;
      addr = '0;
      write_data = '0;
      write_strobe = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b0;
      addr = 32'h4000_7000 + offset;
      #1 value = read_data;
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

  logic [31:0] value;

  initial begin
    req = 1'b0;
    write = 1'b0;
    addr = '0;
    write_data = '0;
    write_strobe = '0;
    sources = '0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    read_reg(8'h00, value);
    check(value == 32'h0000_0000, "IRQCTRL must reset with no pending events");
    check(irq_vector == 32'h0000_0000, "IRQCTRL must reset with all sources masked");

    write_reg_strobe(8'h04, IRQ_TIMER0, 4'b0001);
    read_reg(8'h04, value);
    check(value == 32'h0000_0000,
          "IRQCTRL partial MMIO writes must not enable a torn interrupt mask");

    // A one-cycle timer source is retained even while disabled.
    @(negedge clk);
    sources[2] = 1'b1;
    @(negedge clk);
    sources[2] = 1'b0;
    @(negedge clk);
    read_reg(8'h00, value);
    check((value & IRQ_TIMER0) != 0, "IRQCTRL must latch a short timer source");
    check(irq_vector == 32'h0000_0000, "disabled pending events must not reach the CPU");

    write_reg(8'h04, IRQ_TIMER0);
    @(negedge clk);
    check((irq_vector & IRQ_TIMER0) != 0, "enabled pending timer event must reach CPU IRQ 10");
    read_reg(8'h10, value);
    check(value == IRQ_TIMER0, "ACTIVE must report the enabled pending timer source");
    read_reg(8'h14, value);
    check(value == 32'd10, "HIGHEST must return the CPU IRQ bit index");

    write_reg(8'h08, IRQ_TIMER0);
    @(negedge clk);
    check((irq_vector & IRQ_TIMER0) == 0, "CLEAR must release a deasserted source");
    read_reg(8'h00, value);
    check((value & IRQ_TIMER0) == 0, "CLEAR must remove a sticky timer event");

    // Software forcing uses the same stable CPU IRQ mask ABI as hardware.
    write_reg(8'h0c, IRQ_UART0);
    write_reg(8'h04, IRQ_TIMER0 | IRQ_UART0);
    @(negedge clk);
    check((irq_vector & IRQ_UART0) != 0, "FORCE must create a software-pending IRQ");
    read_reg(8'h14, value);
    check(value == 32'd9, "fixed priority must choose the lowest active IRQ number");
    write_reg(8'h08, IRQ_UART0);
    @(negedge clk);
    check((irq_vector & IRQ_UART0) == 0, "CLEAR must acknowledge a software-forced IRQ");

    // FORCE verifies every public source position, including SPI/I2C/WDT, is
    // represented in the fixed CPU-bit ABI rather than a compact index.
    write_reg(8'h0c, 32'h0000_3f00);
    write_reg(8'h04, 32'h0000_3f00);
    @(negedge clk);
    check(irq_vector == 32'h0000_3f00,
          "all six forced sources must map to CPU IRQ bits 8 through 13");
    write_reg(8'h08, 32'h0000_3f00);
    @(negedge clk);
    check(irq_vector == 32'h0000_0000,
          "CLEAR must release every forced public source bit");

    // A live source wins over a coincident software clear.
    @(negedge clk);
    sources[0] = 1'b1;
    write_reg(8'h04, IRQ_GPIO0);
    write_reg(8'h08, IRQ_GPIO0);
    @(negedge clk);
    check((irq_vector & IRQ_GPIO0) != 0, "a live source must win over CLEAR in the same cycle");
    sources[0] = 1'b0;
    write_reg(8'h08, IRQ_GPIO0);
    @(negedge clk);
    check((irq_vector & IRQ_GPIO0) == 0, "source clears only after it deasserts and firmware acknowledges it");

    $display("PASS: omcu_irq_ctrl_tb");
    $finish;
  end
endmodule

`default_nettype wire
