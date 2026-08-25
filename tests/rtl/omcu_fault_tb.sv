`default_nettype none
`timescale 1ns / 1ps

module omcu_fault_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic fault_in;
  logic input_claim;
  logic [31:0] ticks;
  logic [3:0] gpio_in;
  logic [31:0] irq_active;
  logic [31:0] reset_cause;
  logic irq;
  logic trip;
  logic pwm0_kill;
  logic pwm1_kill;
  logic [3:0] gpio_hiz;

  always #5 clk = ~clk;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) ticks <= 32'h0000_0000;
    else ticks <= ticks + 32'd1;
  end

  omcu_fault #(.GPIO_COUNT(4)) dut (
    .clk_i(clk), .rst_ni(rst_n), .req_i(req), .write_i(write), .addr_i(addr),
    .write_data_i(wdata), .write_strobe_i(wstrb), .ready_o(), .read_data_o(rdata),
    .error_o(), .fault_i(fault_in), .input_claim_i(input_claim), .run_ticks_i(ticks),
    .gpio_in_i(gpio_in), .irq_active_i(irq_active), .reset_cause_i(reset_cause),
    .irq_o(irq), .trip_o(trip), .pwm0_kill_o(pwm0_kill), .pwm1_kill_o(pwm1_kill),
    .gpio_hiz_mask_o(gpio_hiz)
  );

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b1; addr = {24'h40000e, offset}; wdata = data; wstrb = 4'hf;
      @(negedge clk);
      req = 1'b0; write = 1'b0; addr = '0; wdata = '0; wstrb = '0;
    end
  endtask

  task automatic read_reg(input logic [7:0] offset, output logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1; write = 1'b0; addr = {24'h40000e, offset}; #1 data = rdata;
      @(negedge clk);
      req = 1'b0; addr = '0;
    end
  endtask

  task automatic check(input logic condition, input string message);
    begin if (!condition) begin $error("%s", message); $fatal(1); end end
  endtask

  logic [31:0] status;
  logic [31:0] snapshot_gpio;
  logic [31:0] snapshot_irq;
  logic [31:0] snapshot_reset;
  logic [31:0] snapshot_tick;
  initial begin
    req = 0; write = 0; addr = '0; wdata = '0; wstrb = '0;
    fault_in = 0; input_claim = 0; gpio_in = 4'b1010;
    irq_active = 32'h0001_2300; reset_cause = 32'h0000_0002;
    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg(8'h04, 32'd1);
    write_reg(8'h08, 32'h0000_000a);
    write_reg(8'h00, 32'h0000_003f);

    // An unclaimed raw input is never permitted to trip the hardware path.
    fault_in = 1'b1;
    repeat (8) @(negedge clk);
    check(!trip && !irq && !pwm0_kill && gpio_hiz == 4'b0000,
          "FAULT0 must ignore an unclaimed input even when enabled in software");

    input_claim = 1'b1;
    repeat (3) @(negedge clk);
    check(trip && irq && pwm0_kill && pwm1_kill && gpio_hiz == 4'b1010,
          "claimed active fault must latch and force configured outputs safe");
    read_reg(8'h18, snapshot_gpio);
    read_reg(8'h1c, snapshot_irq);
    read_reg(8'h20, snapshot_reset);
    read_reg(8'h14, snapshot_tick);
    check(snapshot_gpio == 32'h0000_000a && snapshot_irq == irq_active &&
          snapshot_reset == reset_cause && snapshot_tick != 32'h0000_0000,
          "FAULT0 first trip must record GPIO, IRQ, reset cause and timestamp");

    write_reg(8'h10, 32'hfa17_c1ea);
    read_reg(8'h0c, status);
    check(trip && status[3],
          "clear must be rejected while the claimed filtered fault remains active");

    fault_in = 1'b0;
    repeat (5) @(negedge clk);
    write_reg(8'h10, 32'hfa17_c1ea);
    @(negedge clk);
    check(!trip && !irq && !pwm0_kill && !pwm1_kill && gpio_hiz == 4'b0000,
          "only an inactive claimed input plus exact magic may release FAULT0");

    $display("PASS: omcu_fault_tb");
    $finish;
  end
endmodule

`default_nettype wire
