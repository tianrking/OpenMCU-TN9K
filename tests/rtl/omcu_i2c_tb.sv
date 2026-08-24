`default_nettype none
`timescale 1ns / 1ps

module omcu_i2c_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic req;
  logic write;
  logic [31:0] addr;
  logic [31:0] wdata;
  logic [3:0] wstrb;
  logic [31:0] rdata;
  logic scl_drive_low;
  logic sda_drive_low;
  logic irq;

  logic slave_scl_drive_low;
  logic slave_sda_drive_low;
  wire scl_line;
  wire sda_line;

  logic write_protocol_active;
  logic read_protocol_active;
  logic slave_ack_enabled;
  logic [7:0] write_capture;
  integer write_bit_count;
  integer read_bit_count;
  integer start_count;
  integer stop_count;
  logic master_nack_seen;
  localparam logic [7:0] RX_EXPECTED = 8'h3c;

  assign scl_line = (scl_drive_low || slave_scl_drive_low) ? 1'b0 : 1'b1;
  assign sda_line = (sda_drive_low || slave_sda_drive_low) ? 1'b0 : 1'b1;

  always #5 clk = ~clk;

  omcu_i2c dut (
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
    .scl_i(scl_line),
    .sda_i(sda_line),
    .scl_drive_low_o(scl_drive_low),
    .sda_drive_low_o(sda_drive_low),
    .irq_o(irq)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  task automatic write_reg(input logic [7:0] offset, input logic [31:0] data);
    begin
      @(negedge clk);
      req = 1'b1;
      write = 1'b1;
      addr = {24'h400004, offset};
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
      addr = {24'h400004, offset};
      #1 data = rdata;
      @(negedge clk);
      req = 1'b0;
      addr = '0;
    end
  endtask

  task automatic wait_for_completion;
    integer cycles;
    begin : wait_loop
      for (cycles = 0; cycles < 1000; cycles = cycles + 1) begin
        @(negedge clk);
        if (!dut.busy_q) begin
          disable wait_loop;
        end
      end
      $error("I2C command did not complete");
      $fatal(1);
    end
  endtask

  // The slave fixture ACKs a commanded write on the ninth clock.  It also
  // captures the byte so this test validates true MSB-first I2C timing rather
  // than merely looking at the controller's internal shift register.
  always @(posedge scl_line) begin
    if (rst_n && write_protocol_active) begin
      if (write_bit_count < 8) begin
        write_capture = {write_capture[6:0], sda_line};
        write_bit_count = write_bit_count + 1;
      end else if (write_bit_count == 8) begin
        check(slave_ack_enabled ? !sda_line : sda_line,
              "slave ACK/NACK level must be visible on the ninth I2C clock");
        write_bit_count = 9;
      end
    end

    if (rst_n && read_protocol_active) begin
      if (read_bit_count < 8) begin
        check(sda_line == RX_EXPECTED[7 - read_bit_count],
              "I2C master must sample target data MSB first");
        read_bit_count = read_bit_count + 1;
      end else if (read_bit_count == 8) begin
        master_nack_seen = sda_line;
        read_bit_count = 9;
      end
    end
  end

  always @(negedge scl_line) begin
    if (rst_n && write_protocol_active) begin
      if (write_bit_count == 8) begin
        slave_sda_drive_low = slave_ack_enabled;
      end else if (write_bit_count == 9) begin
        slave_sda_drive_low = 1'b0;
      end
    end

    if (rst_n && read_protocol_active) begin
      if (read_bit_count < 8) begin
        slave_sda_drive_low = !RX_EXPECTED[7 - read_bit_count];
      end else begin
        slave_sda_drive_low = 1'b0;
      end
    end
  end

  always @(negedge sda_line) begin
    if (rst_n && scl_line) begin
      start_count = start_count + 1;
    end
  end

  always @(posedge sda_line) begin
    if (rst_n && scl_line) begin
      stop_count = stop_count + 1;
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
    slave_scl_drive_low = 1'b0;
    slave_sda_drive_low = 1'b0;
    write_protocol_active = 1'b0;
    read_protocol_active = 1'b0;
    slave_ack_enabled = 1'b1;
    write_capture = 8'h00;
    write_bit_count = 0;
    read_bit_count = 0;
    start_count = 0;
    stop_count = 0;
    master_nack_seen = 1'b0;

    repeat (3) @(negedge clk);
    rst_n = 1'b1;

    write_reg(8'h08, 32'd1);       // Two system clocks per I2C half phase.
    write_reg(8'h0c, 32'h00000003); // Enable and enable DONE interrupt.

    // A byte command outside an active START/STOP transaction is rejected
    // synchronously rather than silently changing the shared bus.
    write_reg(8'h10, 32'h00000004);
    read_reg(8'h04, status);
    check(status[1] && status[3] && !status[0],
          "I2C must flag a WRITE command outside an owned transaction");
    write_reg(8'h04, 32'h0000000e);

    write_reg(8'h10, 32'h00000001);
    wait_for_completion();
    read_reg(8'h04, status);
    check(status[1] && status[4] && irq,
          "START must complete, own the bus and assert the enabled DONE IRQ");
    check(start_count == 1 && stop_count == 0,
          "initial START must change SDA low while SCL is high without STOP");
    write_reg(8'h04, 32'h0000000e);

    // Hold SCL low after the controller releases it.  The command must wait
    // for the target to release the clock before producing any data edge.
    write_capture = 8'h00;
    write_bit_count = 0;
    slave_ack_enabled = 1'b1;
    write_protocol_active = 1'b1;
    slave_scl_drive_low = 1'b1;
    write_reg(8'h00, 32'h000000a5);
    write_reg(8'h10, 32'h00000004);
    repeat (12) @(negedge clk);
    check(write_bit_count == 0,
          "clock stretching must prevent data sampling while SCL remains low");
    slave_scl_drive_low = 1'b0;
    wait_for_completion();
    read_reg(8'h04, status);
    check(status[1] && !status[2] && !status[3] && irq,
          "ACKed write must complete without I2C error status");
    check(write_bit_count == 9 && write_capture == 8'ha5,
          "I2C write must emit eight MSB-first bits plus an ACK clock");
    write_protocol_active = 1'b0;
    slave_sda_drive_low = 1'b0;
    write_reg(8'h04, 32'h0000000e);

    // This is a true repeated START: SDA first releases while SCL is low,
    // then falls while SCL is high.  There must be no accidental STOP.
    write_reg(8'h10, 32'h00000001);
    wait_for_completion();
    check(start_count == 2 && stop_count == 0,
          "repeated START must not release the bus as a STOP");
    write_reg(8'h04, 32'h0000000e);

    read_bit_count = 0;
    master_nack_seen = 1'b0;
    read_protocol_active = 1'b1;
    slave_sda_drive_low = !RX_EXPECTED[7];
    write_reg(8'h10, 32'h00000010); // Read one byte and NACK it.
    wait_for_completion();
    read_reg(8'h00, received);
    read_reg(8'h04, status);
    check(received[7:0] == RX_EXPECTED,
          "I2C DATA must expose the received byte after a read command");
    check(read_bit_count == 9 && master_nack_seen,
          "READ_NACK must release SDA for the ninth I2C clock");
    check(status[1] && !status[2] && !status[3],
          "read completion must not claim a write ACK error");
    read_protocol_active = 1'b0;
    slave_sda_drive_low = 1'b0;
    write_reg(8'h04, 32'h0000000e);

    write_reg(8'h10, 32'h00000002);
    wait_for_completion();
    read_reg(8'h04, status);
    check(status[1] && !status[4] && scl_line && sda_line,
          "STOP must release both open-drain lines and bus ownership");
    check(stop_count == 1,
          "STOP must raise SDA while SCL is high exactly once");
    write_reg(8'h04, 32'h0000000e);

    // Exercise the sticky NACK path separately.  Firmware can therefore
    // distinguish an address/data NACK from an invalid command sequence.
    write_reg(8'h10, 32'h00000001);
    wait_for_completion();
    write_reg(8'h04, 32'h0000000e);
    write_capture = 8'h00;
    write_bit_count = 0;
    slave_ack_enabled = 1'b0;
    write_protocol_active = 1'b1;
    write_reg(8'h00, 32'h0000005a);
    write_reg(8'h10, 32'h00000004);
    wait_for_completion();
    read_reg(8'h04, status);
    check(status[1] && status[2] && !status[3],
          "released ninth clock must latch I2C ACK_ERROR");
    write_protocol_active = 1'b0;
    slave_sda_drive_low = 1'b0;
    write_reg(8'h04, 32'h00000006);
    read_reg(8'h04, status);
    check(!status[1] && !status[2], "DONE and ACK_ERROR must be write-one-to-clear");
    write_reg(8'h10, 32'h00000002);
    wait_for_completion();

    $display("PASS: omcu_i2c_tb");
    $finish;
  end
endmodule

`default_nettype wire
