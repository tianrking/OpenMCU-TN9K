`default_nettype none
`timescale 1ns / 1ps

module omcu_timer1_tb;
  localparam logic [31:0] CTRL_ENABLE            = 32'h0000_0001;
  localparam logic [31:0] CTRL_IRQ_ENABLE        = 32'h0000_0002;
  localparam logic [31:0] CTRL_AUTO_RELOAD       = 32'h0000_0004;
  localparam logic [31:0] CTRL_CAPTURE_A_ENABLE  = 32'h0000_0008;
  localparam logic [31:0] CTRL_CAPTURE_B_ENABLE  = 32'h0000_0010;
  localparam logic [31:0] CTRL_CAPTURE_B_FALLING = 32'h0000_0040;
  localparam logic [31:0] CTRL_QUADRATURE_ENABLE = 32'h0000_0080;
  localparam logic [31:0] STATUS_COMPARE          = 32'h0000_0001;
  localparam logic [31:0] STATUS_CAPTURE_A        = 32'h0000_0002;
  localparam logic [31:0] STATUS_CAPTURE_B        = 32'h0000_0004;
  localparam logic [31:0] STATUS_ENCODER_STEP     = 32'h0000_0008;
  localparam logic [31:0] STATUS_ENCODER_ILLEGAL  = 32'h0000_0010;

  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic capture_a;
  logic capture_b;
  logic irq;

  always #5 clk = ~clk;

  omcu_timer1 dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .capture_a_i(capture_a), .capture_b_i(capture_b), .irq_o(irq)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h400009, offset};
      wdata = value; wstrb = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic write_reg_strobe(
    input logic [7:0] offset,
    input logic [31:0] value,
    input logic [3:0] strobe
  );
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h400009, offset};
      wdata = value; wstrb = strobe;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b0; addr = {24'h400009, offset}; wdata = '0; wstrb = '0;
      #1 value = rdata;
      @(negedge clk);
      req = 1'b0; addr = '0;
    end
  endtask

  task automatic drive_inputs(
    input logic a_value,
    input logic b_value,
    input integer settle_edges
  );
    begin
      capture_a = a_value;
      capture_b = b_value;
      repeat (settle_edges) @(negedge clk);
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
    req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    capture_a = 1'b0; capture_b = 1'b0;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg_strobe(8'h00, CTRL_ENABLE | CTRL_IRQ_ENABLE, 4'b0001);
    check(!dut.timer_enable_q,
          "TIMER1 partial MMIO writes must not create a torn configuration");

    // TIMER1 retains TIMER0's one-shot/periodic compare contract and exposes
    // its event through the optional IRQ output.
    write_reg(8'h04, 32'd0);
    write_reg(8'h08, 32'd0);
    write_reg(8'h0c, 32'd2);
    write_reg(8'h00, CTRL_ENABLE | CTRL_IRQ_ENABLE | CTRL_AUTO_RELOAD);
    repeat (5) @(negedge clk);
    check(irq, "TIMER1 compare must assert its enabled IRQ");
    write_reg(8'h00, 32'd0);
    write_reg(8'h20, STATUS_COMPARE);
    @(negedge clk);
    check(!irq, "TIMER1 STATUS.COMPARE W1C must release a stopped timer IRQ");

    // FILTER=2 requires three consecutive synchronized mismatched samples.
    // A one-cycle asynchronous pulse must therefore not become a capture.
    write_reg(8'h10, 32'd2);
    write_reg(8'h08, 32'h1234_5678);
    write_reg(8'h00, CTRL_CAPTURE_A_ENABLE);
    write_reg(8'h20, 32'h0000_001f);
    drive_inputs(1'b1, 1'b0, 1);
    drive_inputs(1'b0, 1'b0, 6);
    read_reg(8'h20, value);
    check((value & STATUS_CAPTURE_A) == 0,
          "short A pulse must be rejected before capture after the synchronizer filter");

    drive_inputs(1'b1, 1'b0, 7);
    read_reg(8'h20, value);
    check((value & STATUS_CAPTURE_A) != 0,
          "stable A edge must become a filtered capture event");
    read_reg(8'h14, value);
    check(value == 32'h0000_5678,
          "CAPTURE_A must retain TIMER1's low-16-bit timestamp rather than raw input time");
    write_reg(8'h20, STATUS_CAPTURE_A);
    drive_inputs(1'b0, 1'b0, 7);

    // Channel B also supports an independently selected falling-edge capture.
    write_reg(8'h10, 32'd0);
    drive_inputs(1'b0, 1'b1, 5);
    write_reg(8'h08, 32'h89ab_cdef);
    write_reg(8'h00, CTRL_CAPTURE_B_ENABLE | CTRL_CAPTURE_B_FALLING);
    write_reg(8'h20, 32'h0000_001f);
    drive_inputs(1'b0, 1'b0, 5);
    read_reg(8'h20, value);
    check((value & STATUS_CAPTURE_B) != 0,
          "selected B falling edge must create a capture event");
    read_reg(8'h18, value);
    check(value == 32'h0000_cdef, "CAPTURE_B must retain its own low-16-bit timestamp");

    // Forward Gray sequence: 00 -> 01 -> 11 -> 10 -> 00.  The filtered
    // decoder must count every legal transition exactly once.
    write_reg(8'h00, CTRL_QUADRATURE_ENABLE);
    write_reg(8'h1c, 32'd0);
    write_reg(8'h20, 32'h0000_001f);
    drive_inputs(1'b0, 1'b0, 5);
    drive_inputs(1'b0, 1'b1, 5);
    drive_inputs(1'b1, 1'b1, 5);
    drive_inputs(1'b1, 1'b0, 5);
    drive_inputs(1'b0, 1'b0, 5);
    read_reg(8'h1c, value);
    check(value == 32'd4, "four legal forward quadrature transitions must increment position");
    read_reg(8'h20, value);
    check((value & STATUS_ENCODER_STEP) != 0 && value[7],
          "quadrature status must record a step and the latest forward direction");

    // Reverse transitions return to zero and update the direction observation.
    write_reg(8'h20, STATUS_ENCODER_STEP);
    drive_inputs(1'b1, 1'b0, 5);
    drive_inputs(1'b1, 1'b1, 5);
    drive_inputs(1'b0, 1'b1, 5);
    drive_inputs(1'b0, 1'b0, 5);
    read_reg(8'h1c, value);
    check(value == 32'd0, "four legal reverse transitions must decrement position");
    read_reg(8'h20, value);
    check((value & STATUS_ENCODER_STEP) != 0 && !value[7],
          "quadrature status must expose the latest reverse direction");

    // A simultaneous 00 -> 11 transition is not silently treated as two
    // steps; it reports an illegal Gray transition for fault diagnostics.
    write_reg(8'h1c, 32'd0);
    write_reg(8'h20, 32'h0000_001f);
    drive_inputs(1'b1, 1'b1, 5);
    read_reg(8'h1c, value);
    check(value == 32'd0, "illegal Gray transition must not alter encoder position");
    read_reg(8'h20, value);
    check((value & STATUS_ENCODER_ILLEGAL) != 0,
          "illegal Gray transition must be visible as a sticky status event");

    // Restore 00, enable delivery, then check the same filtered step reaches
    // the TIMER1 IRQ endpoint.  IRQCTRL mapping is verified separately.
    write_reg(8'h20, 32'h0000_001f);
    drive_inputs(1'b0, 1'b0, 5);
    write_reg(8'h00, CTRL_QUADRATURE_ENABLE | CTRL_IRQ_ENABLE);
    write_reg(8'h20, 32'h0000_001f);
    drive_inputs(1'b0, 1'b1, 5);
    check(irq, "filtered quadrature step must assert TIMER1 IRQ when enabled");

    $display("PASS: omcu_timer1_tb");
    $finish;
  end
endmodule

`default_nettype wire
