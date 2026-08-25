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
  logic [31:0] run_ticks;
  logic [31:0] irq_active;
  logic [31:0] reset_cause;
  logic irq;

  always #5 clk = ~clk;
  always_ff @(posedge clk or negedge rst_n) begin
    if (!rst_n) run_ticks <= 32'h0000_0000;
    else run_ticks <= run_ticks + 32'd1;
  end

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
    .run_ticks_i(run_ticks),
    .irq_active_i(irq_active),
    .reset_cause_i(reset_cause),
    .snapshot_force_i(1'b0),
    .snapshot_tick_o(),
    .snapshot_gpio_o(),
    .snapshot_irq_o(),
    .snapshot_reset_o(),
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
      address = '0;
      write_data = '0;
      write_strobe = '0;
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
      address = '0;
      write_data = '0;
      write_strobe = '0;
    end
  endtask

  task automatic mmio_read(input logic [31:0] offset, output logic [31:0] value);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b0;
      address = offset;
      #1 value = read_data;
      @(negedge clk);
      req = 1'b0;
      address = '0;
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

  logic [31:0] snapshot_status;
  logic [31:0] snapshot_event;
  logic [31:0] snapshot_input;
  logic [31:0] snapshot_irq;
  logic [31:0] snapshot_reset;
  logic [31:0] snapshot_ticks;
  initial begin
    req = 1'b0;
    write = 1'b0;
    address = '0;
    write_data = '0;
    write_strobe = '0;
    gpio_in = '0;
    irq_active = 32'h0000_0100;
    reset_cause = 32'h0000_0002;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;
    repeat (4) @(negedge clk);

    mmio_write_strobe(32'h0000_0014, 32'h0000_000f, 4'b0001);
    check(gpio_oe == 4'b0000,
          "GPIO partial MMIO writes must not create a torn output-enable mask");

    mmio_write(32'h0000_0014, 32'h0000_0003);
    check(gpio_oe == 4'b0011, "GPIO output-enable set must affect selected pins");

    mmio_write(32'h0000_0004, 32'h0000_0005);
    check(gpio_out == 4'b0101, "GPIO output set must affect selected pins");

    mmio_write(32'h0000_0008, 32'h0000_0001);
    check(gpio_out == 4'b0100, "GPIO output clear must clear selected pins");

    // GPIO2 remains unfiltered, but it is still observed only after the
    // documented two-flop synchronization path.
    mmio_write(32'h0000_0024, 32'h0000_0004);
    gpio_in = 4'b0000;
    repeat (4) @(negedge clk);
    gpio_in = 4'b0100;
    repeat (4) @(negedge clk);
    check(irq, "synchronized rising input edge must assert GPIO interrupt");

    mmio_write(32'h0000_002c, 32'h0000_0004);
    @(negedge clk);
    check(!irq, "GPIO W1C must clear a latched interrupt");

    // GPIO1 uses a three-sample whole-port stability filter
    // (FILTER_CYCLES=2). GPIO2 is deliberately changed so the test can verify
    // that a change on any input restarts the shared window.
    // A short synchronized GPIO1 pulse must not reach either the IRQ edge
    // detector or the first-event snapshot.
    mmio_write(32'h0000_0024, 32'h0000_0002);
    mmio_write(32'h0000_0034, 32'h0000_0002);
    mmio_write(32'h0000_003c, 32'h0000_0002);
    mmio_write(32'h0000_0040, 32'h0000_0000);
    mmio_write(32'h0000_0038, 32'h0000_0003);
    gpio_in = 4'b0110;
    @(negedge clk);
    gpio_in = 4'b0100;
    repeat (8) @(negedge clk);
    check(!irq && !dut.snapshot_valid_q,
          "a pulse shorter than the selected digital filter must be rejected");

    // GPIO1 stays high, but a change on another GPIO must restart the one
    // shared settling window instead of accepting GPIO1 independently.
    gpio_in = 4'b0110;
    repeat (2) @(negedge clk);
    gpio_in = 4'b0010;
    repeat (4) @(negedge clk);
    check(!irq && !dut.snapshot_valid_q && !dut.gpio_filtered_q[1],
          "any selected GPIO change must restart the shared filter window");

    // A stable selected group is accepted after synchronizer plus filter
    // latency. GPIO2 does not have its edge enabled, so only GPIO1 produces
    // the IRQ and diagnostic snapshot.
    gpio_in = 4'b0110;
    repeat (9) @(negedge clk);
    check(irq, "snapshot IRQ must share GPIO0 once the filtered edge is accepted");
    mmio_read(32'h0000_0044, snapshot_status);
    mmio_read(32'h0000_0048, snapshot_event);
    mmio_read(32'h0000_004c, snapshot_input);
    mmio_read(32'h0000_0050, snapshot_irq);
    mmio_read(32'h0000_0054, snapshot_reset);
    mmio_read(32'h0000_0058, snapshot_ticks);
    check(snapshot_status[0] && !snapshot_status[1],
          "first GPIO snapshot must become valid without overflow");
    check(snapshot_event == 32'h0000_0002 && snapshot_input[1],
          "snapshot must record the filtered edge mask and post-edge GPIO state");
    check(snapshot_irq == irq_active && snapshot_reset == reset_cause &&
          snapshot_ticks != 32'h0000_0000,
          "snapshot must include active IRQs, retained reset cause and timestamp");

    // The first-event policy retains the useful initial state and records an
    // overflow when a second selected edge arrives before software consumes it.
    mmio_write(32'h0000_0040, 32'h0000_0002);
    gpio_in = 4'b0100;
    repeat (9) @(negedge clk);
    mmio_read(32'h0000_0044, snapshot_status);
    mmio_read(32'h0000_004c, snapshot_input);
    check(snapshot_status[0] && snapshot_status[1] && snapshot_input[1],
          "second event must set overflow while retaining the original snapshot");

    mmio_write(32'h0000_0044, 32'h0000_0003);
    mmio_write(32'h0000_002c, 32'h0000_0002);
    @(negedge clk);
    mmio_read(32'h0000_0044, snapshot_status);
    check(!snapshot_status[0] && !snapshot_status[1] && !irq,
          "snapshot VALID and OVERFLOW must be independently W1C-clearable");

    $display("PASS: omcu_gpio_tb");
    $finish;
  end
endmodule

`default_nettype wire
