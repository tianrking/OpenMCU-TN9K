`default_nettype none
`timescale 1ns / 1ps

// Compiler-to-bus integration test.  The target fixture is intentionally a
// tiny open-drain I2C device: it ACKs a 0x50 write transaction and returns
// 0x3C after a read address.  The firmware exercises only public SDK helpers.
module omcu_i2c_sdk_tb;
  logic clk = 1'b0;
  logic rst_n = 1'b0;
  logic [3:0] gpio_out;
  logic [3:0] gpio_oe;
  logic i2c_scl_drive_low;
  logic i2c_sda_drive_low;
  logic slave_sda_drive_low;
  wire i2c_scl_line;
  wire i2c_sda_line;
  logic cpu_trap;
  logic bus_error;
  logic bus_error_seen = 1'b0;
  logic [7:0] captured_bytes [0:3];
  logic transaction_active;
  logic address_phase;
  logic read_mode;
  logic ack_drive_active;
  logic [7:0] write_capture;
  integer write_bit_count;
  integer captured_byte_count;
  integer read_bit_count;
  integer start_count;
  integer stop_count;
  logic master_nack_seen;
  localparam logic [7:0] TARGET_RESPONSE = 8'h3c;

  assign i2c_scl_line = i2c_scl_drive_low ? 1'b0 : 1'b1;
  assign i2c_sda_line = (i2c_sda_drive_low || slave_sda_drive_low) ? 1'b0 : 1'b1;

  always #5 clk = ~clk;

  always @(posedge clk) begin
    if (bus_error) bus_error_seen <= 1'b1;
  end

  omcu_picorv32_system #(
    .GPIO_COUNT(4),
    // I2C helper calls spill registers to the stack, so this must use the
    // The generic bring-up SDK regression remains an 8 KiB ROM / 44 KiB SRAM
    // target. The customer-facing product wrapper has its separate 4 KiB
    // boot ROM and User-Flash path.
    .ROM_WORDS(2048),
    .SRAM_BYTES(45056),
    .ROM_INIT_FILE("build/sdk/omcu_i2c_smoke.hex")
  ) dut (
    .clk_i(clk),
    .rst_ni(rst_n),
    .gpio_in_i(4'b0000),
    .gpio_out_o(gpio_out),
    .gpio_oe_o(gpio_oe),
    .gpio_irq_o(),
    .uart_rx_i(1'b1),
    .uart_tx_o(),
    .uart_irq_o(),
    .timer_irq_o(),
    .spi_miso_i(1'b1),
    .spi_mosi_o(),
    .spi_sck_o(),
    .spi_cs_n_o(),
    .spi_irq_o(),
    .i2c_scl_i(i2c_scl_line),
    .i2c_sda_i(i2c_sda_line),
    .i2c_scl_drive_low_o(i2c_scl_drive_low),
    .i2c_sda_drive_low_o(i2c_sda_drive_low),
    .i2c_irq_o(),
    .wdt_irq_o(),
    .wdt_reset_req_o(),
    .pwm_o(),
    .cpu_trap_o(cpu_trap),
    .bus_error_o(bus_error)
  );

  task automatic check(input logic condition, input string message);
    begin
      if (!condition) begin
        $error("%s", message);
        $fatal(1);
      end
    end
  endtask

  always @(negedge i2c_sda_line) begin
    if (rst_n && i2c_scl_line) begin
      transaction_active = 1'b1;
      address_phase = 1'b1;
      read_mode = 1'b0;
      ack_drive_active = 1'b0;
      write_bit_count = 0;
      slave_sda_drive_low = 1'b0;
      start_count = start_count + 1;
    end
  end

  always @(posedge i2c_sda_line) begin
    if (rst_n && i2c_scl_line) begin
      transaction_active = 1'b0;
      read_mode = 1'b0;
      slave_sda_drive_low = 1'b0;
      stop_count = stop_count + 1;
    end
  end

  always @(posedge i2c_scl_line) begin
    if (rst_n && transaction_active) begin
      if (!read_mode) begin
        if (!ack_drive_active && write_bit_count < 8) begin
          write_capture = {write_capture[6:0], i2c_sda_line};
          write_bit_count = write_bit_count + 1;
        end
      end else if (read_bit_count < 8) begin
        check(i2c_sda_line == TARGET_RESPONSE[7 - read_bit_count],
              "SDK I2C read must sample the target response MSB first");
        read_bit_count = read_bit_count + 1;
      end else if (read_bit_count == 8) begin
        master_nack_seen = i2c_sda_line;
        read_bit_count = 9;
      end
    end
  end

  always @(negedge i2c_scl_line) begin
    if (rst_n && transaction_active) begin
      if (!read_mode) begin
        if (!ack_drive_active && write_bit_count == 8) begin
          slave_sda_drive_low = 1'b1;
          ack_drive_active = 1'b1;
        end else if (ack_drive_active) begin
          slave_sda_drive_low = 1'b0;
          ack_drive_active = 1'b0;
          captured_bytes[captured_byte_count] = write_capture;
          captured_byte_count = captured_byte_count + 1;
          if (address_phase && write_capture[0]) begin
            read_mode = 1'b1;
            read_bit_count = 0;
            slave_sda_drive_low = !TARGET_RESPONSE[7];
          end
          address_phase = 1'b0;
          write_bit_count = 0;
        end
      end else if (read_bit_count < 8) begin
        slave_sda_drive_low = !TARGET_RESPONSE[7 - read_bit_count];
      end else begin
        slave_sda_drive_low = 1'b0;
      end
    end
  end

  initial begin
    slave_sda_drive_low = 1'b0;
    transaction_active = 1'b0;
    address_phase = 1'b0;
    read_mode = 1'b0;
    ack_drive_active = 1'b0;
    write_capture = 8'h00;
    write_bit_count = 0;
    captured_byte_count = 0;
    read_bit_count = 0;
    start_count = 0;
    stop_count = 0;
    master_nack_seen = 1'b0;

    repeat (4) @(negedge clk);
    rst_n = 1'b1;
    repeat (10000) @(negedge clk);

    check(!cpu_trap, "compiled I2C SDK firmware must not trap");
    check(!bus_error_seen, "compiled I2C SDK firmware must not hit an invalid address");
    check(gpio_oe[0] && gpio_oe[1], "I2C SDK firmware must configure pass/fail GPIO");
    check(gpio_out[0] && !gpio_out[1], "I2C SDK firmware must report success");
    check(start_count == 2 && stop_count == 2,
          "SDK helper sequence must emit two START and two STOP conditions");
    check(captured_byte_count == 3 &&
          captured_bytes[0] == 8'ha0 &&
          captured_bytes[1] == 8'h5a &&
          captured_bytes[2] == 8'ha1,
          "SDK I2C helper sequence must emit address, payload and read address bytes");
    check(read_bit_count == 9 && master_nack_seen,
          "SDK final-byte read must NACK the target before STOP");

    $display("PASS: omcu_i2c_sdk_tb");
    $finish;
  end
endmodule

`default_nettype wire
