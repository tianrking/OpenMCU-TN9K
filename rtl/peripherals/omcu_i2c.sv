`default_nettype none

// A compact, polling-friendly I2C master byte engine.  It drives only the
// low side of SCL/SDA; the platform wrapper supplies the open-drain pads and
// input synchronizers.  Commands deliberately stay byte-granular so an SDK
// can form standard write, repeated-START and read transactions without a
// hidden fixed address or an implicit STOP.
module omcu_i2c (
  input  logic        clk_i,
  input  logic        rst_ni,

  input  logic        req_i,
  input  logic        write_i,
  input  logic [31:0] addr_i,
  input  logic [31:0] write_data_i,
  input  logic [3:0]  write_strobe_i,
  output logic        ready_o,
  output logic [31:0] read_data_o,
  output logic        error_o,

  input  logic        scl_i,
  input  logic        sda_i,
  output logic        scl_drive_low_o,
  output logic        sda_drive_low_o,
  output logic        irq_o
);

  localparam logic [5:0] REG_DATA   = 6'h00;
  localparam logic [5:0] REG_STATUS = 6'h01;
  localparam logic [5:0] REG_CLKDIV = 6'h02;
  localparam logic [5:0] REG_CTRL   = 6'h03;
  localparam logic [5:0] REG_CMD    = 6'h04;

  localparam logic [4:0] CMD_START     = 5'b00001;
  localparam logic [4:0] CMD_STOP      = 5'b00010;
  localparam logic [4:0] CMD_WRITE     = 5'b00100;
  localparam logic [4:0] CMD_READ_ACK  = 5'b01000;
  localparam logic [4:0] CMD_READ_NACK = 5'b10000;

  localparam logic [4:0] ST_IDLE                 = 5'd0;
  localparam logic [4:0] ST_START_WAIT_BUS       = 5'd1;
  localparam logic [4:0] ST_RESTART_SDA_RELEASE  = 5'd2;
  localparam logic [4:0] ST_RESTART_SCL_RELEASE  = 5'd3;
  localparam logic [4:0] ST_START_SDA_LOW        = 5'd4;
  localparam logic [4:0] ST_START_SCL_LOW        = 5'd5;
  localparam logic [4:0] ST_STOP_LOW             = 5'd6;
  localparam logic [4:0] ST_STOP_SCL_RELEASE     = 5'd7;
  localparam logic [4:0] ST_WRITE_DRIVE          = 5'd8;
  localparam logic [4:0] ST_WRITE_RISE           = 5'd9;
  localparam logic [4:0] ST_WRITE_FALL           = 5'd10;
  localparam logic [4:0] ST_WRITE_ACK_DRIVE      = 5'd11;
  localparam logic [4:0] ST_WRITE_ACK_RISE       = 5'd12;
  localparam logic [4:0] ST_WRITE_ACK_FALL       = 5'd13;
  localparam logic [4:0] ST_READ_DRIVE           = 5'd14;
  localparam logic [4:0] ST_READ_RISE            = 5'd15;
  localparam logic [4:0] ST_READ_FALL            = 5'd16;
  localparam logic [4:0] ST_READ_ACK_DRIVE       = 5'd17;
  localparam logic [4:0] ST_READ_ACK_RISE        = 5'd18;
  localparam logic [4:0] ST_READ_ACK_FALL        = 5'd19;

  logic        enable_q;
  logic        irq_enable_q;
  logic        busy_q;
  logic        done_q;
  logic        ack_error_q;
  logic        command_error_q;
  logic        bus_owned_q;
  logic        read_ack_q;
  logic [15:0] clkdiv_q;
  logic [15:0] div_count_q;
  logic [7:0]  tx_data_q;
  logic [7:0]  rx_data_q;
  logic [7:0]  tx_shift_q;
  logic [7:0]  rx_shift_q;
  logic [2:0]  bit_index_q;
  logic [4:0]  state_q;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;
  logic        full_word_write;

  function automatic logic command_is_one_hot(input logic [4:0] value);
    command_is_one_hot = (value != 5'b00000) &&
                         ((value & (value - 5'b00001)) == 5'b00000);
  endfunction

  function automatic logic state_waits_for_scl_high(input logic [4:0] state);
    case (state)
      ST_WRITE_RISE,
      ST_WRITE_ACK_RISE,
      ST_READ_RISE,
      ST_READ_ACK_RISE,
      ST_STOP_SCL_RELEASE: state_waits_for_scl_high = 1'b1;
      default:             state_waits_for_scl_high = 1'b0;
    endcase
  endfunction

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = done_q & irq_enable_q;
  // I2C byte payloads are carried in an aligned 32-bit DATA command word.
  // Full-word writes make bus configuration and command acknowledgement
  // atomic, avoiding wide byte-lane merge muxes in the FPGA fabric.
  assign full_word_write = write_strobe_i == 4'b1111;

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = irq_enable_q;

    status_read = '0;
    status_read[0] = busy_q;
    status_read[1] = done_q;
    status_read[2] = ack_error_q;
    status_read[3] = command_error_q;
    status_read[4] = bus_owned_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_DATA:   read_data_o = {24'h000000, rx_data_q};
      REG_STATUS: read_data_o = status_read;
      REG_CLKDIV: read_data_o = {16'h0000, clkdiv_q};
      REG_CTRL:   read_data_o = ctrl_read;
      default:    read_data_o = '0;
    endcase
  end

  // Idle-with-ownership deliberately holds SCL low.  This makes commands
  // composable: a completed START/READ/WRITE cannot accidentally turn into a
  // STOP while software is preparing the next byte command.
  always_comb begin
    scl_drive_low_o = 1'b0;
    sda_drive_low_o = 1'b0;

    unique case (state_q)
      ST_IDLE: begin
        if (bus_owned_q) begin
          scl_drive_low_o = 1'b1;
          sda_drive_low_o = 1'b1;
        end
      end
      ST_RESTART_SDA_RELEASE: begin
        scl_drive_low_o = 1'b1;
      end
      ST_START_SDA_LOW: begin
        sda_drive_low_o = 1'b1;
      end
      ST_START_SCL_LOW,
      ST_STOP_LOW: begin
        scl_drive_low_o = 1'b1;
        sda_drive_low_o = 1'b1;
      end
      ST_STOP_SCL_RELEASE: begin
        sda_drive_low_o = 1'b1;
      end
      ST_WRITE_DRIVE,
      ST_WRITE_FALL: begin
        scl_drive_low_o = 1'b1;
        sda_drive_low_o = !tx_shift_q[7];
      end
      ST_WRITE_RISE: begin
        sda_drive_low_o = !tx_shift_q[7];
      end
      ST_WRITE_ACK_DRIVE,
      ST_WRITE_ACK_FALL: begin
        scl_drive_low_o = 1'b1;
      end
      ST_READ_DRIVE,
      ST_READ_FALL: begin
        scl_drive_low_o = 1'b1;
      end
      ST_READ_ACK_DRIVE,
      ST_READ_ACK_FALL: begin
        scl_drive_low_o = 1'b1;
        sda_drive_low_o = read_ack_q;
      end
      ST_READ_ACK_RISE: begin
        sda_drive_low_o = read_ack_q;
      end
      default: begin
      end
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      busy_q <= 1'b0;
      done_q <= 1'b0;
      ack_error_q <= 1'b0;
      command_error_q <= 1'b0;
      bus_owned_q <= 1'b0;
      read_ack_q <= 1'b0;
      clkdiv_q <= 16'd134;
      div_count_q <= 16'h0000;
      tx_data_q <= 8'h00;
      rx_data_q <= 8'h00;
      tx_shift_q <= 8'h00;
      rx_shift_q <= 8'h00;
      bit_index_q <= 3'd0;
      state_q <= ST_IDLE;
    end else begin
      if (busy_q) begin
        // On an open-drain bus the target may stretch the clock.  Once SCL is
        // released, restart the high-phase timer until the sampled line is
        // actually high, then still provide a full configured high phase.
        if (((state_q == ST_START_WAIT_BUS || state_q == ST_RESTART_SCL_RELEASE) &&
             (!scl_i || !sda_i)) ||
            (state_waits_for_scl_high(state_q) && !scl_i)) begin
          div_count_q <= 16'h0000;
        end else if (div_count_q == clkdiv_q) begin
          div_count_q <= 16'h0000;
          unique case (state_q)
            ST_START_WAIT_BUS: begin
              state_q <= ST_START_SDA_LOW;
              bus_owned_q <= 1'b1;
            end
            ST_RESTART_SDA_RELEASE: begin
              state_q <= ST_RESTART_SCL_RELEASE;
            end
            ST_RESTART_SCL_RELEASE: begin
              state_q <= ST_START_SDA_LOW;
            end
            ST_START_SDA_LOW: begin
              state_q <= ST_START_SCL_LOW;
            end
            ST_START_SCL_LOW: begin
              state_q <= ST_IDLE;
              busy_q <= 1'b0;
              done_q <= 1'b1;
            end
            ST_STOP_LOW: begin
              state_q <= ST_STOP_SCL_RELEASE;
            end
            ST_STOP_SCL_RELEASE: begin
              state_q <= ST_IDLE;
              busy_q <= 1'b0;
              bus_owned_q <= 1'b0;
              done_q <= 1'b1;
            end
            ST_WRITE_DRIVE: begin
              state_q <= ST_WRITE_RISE;
            end
            ST_WRITE_RISE: begin
              state_q <= ST_WRITE_FALL;
            end
            ST_WRITE_FALL: begin
              if (bit_index_q == 3'd7) begin
                state_q <= ST_WRITE_ACK_DRIVE;
              end else begin
                bit_index_q <= bit_index_q + 3'd1;
                tx_shift_q <= {tx_shift_q[6:0], 1'b0};
                state_q <= ST_WRITE_DRIVE;
              end
            end
            ST_WRITE_ACK_DRIVE: begin
              state_q <= ST_WRITE_ACK_RISE;
            end
            ST_WRITE_ACK_RISE: begin
              if (sda_i) begin
                ack_error_q <= 1'b1;
              end
              state_q <= ST_WRITE_ACK_FALL;
            end
            ST_WRITE_ACK_FALL: begin
              state_q <= ST_IDLE;
              busy_q <= 1'b0;
              done_q <= 1'b1;
            end
            ST_READ_DRIVE: begin
              state_q <= ST_READ_RISE;
            end
            ST_READ_RISE: begin
              rx_shift_q <= {rx_shift_q[6:0], sda_i};
              state_q <= ST_READ_FALL;
            end
            ST_READ_FALL: begin
              if (bit_index_q == 3'd7) begin
                rx_data_q <= rx_shift_q;
                state_q <= ST_READ_ACK_DRIVE;
              end else begin
                bit_index_q <= bit_index_q + 3'd1;
                state_q <= ST_READ_DRIVE;
              end
            end
            ST_READ_ACK_DRIVE: begin
              state_q <= ST_READ_ACK_RISE;
            end
            ST_READ_ACK_RISE: begin
              state_q <= ST_READ_ACK_FALL;
            end
            ST_READ_ACK_FALL: begin
              state_q <= ST_IDLE;
              busy_q <= 1'b0;
              done_q <= 1'b1;
            end
            default: begin
              state_q <= ST_IDLE;
              busy_q <= 1'b0;
              bus_owned_q <= 1'b0;
              command_error_q <= 1'b1;
            end
          endcase
        end else begin
          div_count_q <= div_count_q + 16'd1;
        end
      end else begin
        div_count_q <= 16'h0000;
      end

      if (req_i && write_i && full_word_write) begin
        unique case (addr_i[7:2])
          REG_DATA: begin
            tx_data_q <= write_data_i[7:0];
          end
          REG_STATUS: begin
            if (write_data_i[1]) done_q <= 1'b0;
            if (write_data_i[2]) ack_error_q <= 1'b0;
            if (write_data_i[3]) command_error_q <= 1'b0;
          end
          REG_CLKDIV: begin
            clkdiv_q <= write_data_i[15:0];
          end
          REG_CTRL: begin
            enable_q <= write_data_i[0];
            irq_enable_q <= write_data_i[1];
            if (!write_data_i[0]) begin
              busy_q <= 1'b0;
              bus_owned_q <= 1'b0;
              state_q <= ST_IDLE;
            end
          end
          REG_CMD: begin
            if (!busy_q) begin
              if (!enable_q || !command_is_one_hot(write_data_i[4:0])) begin
                done_q <= 1'b1;
                command_error_q <= 1'b1;
              end else begin
                unique case (write_data_i[4:0])
                  CMD_START: begin
                    busy_q <= 1'b1;
                    done_q <= 1'b0;
                    ack_error_q <= 1'b0;
                    command_error_q <= 1'b0;
                    state_q <= bus_owned_q ? ST_RESTART_SDA_RELEASE : ST_START_WAIT_BUS;
                  end
                  CMD_STOP: begin
                    if (bus_owned_q) begin
                      busy_q <= 1'b1;
                      done_q <= 1'b0;
                      ack_error_q <= 1'b0;
                      command_error_q <= 1'b0;
                      state_q <= ST_STOP_LOW;
                    end else begin
                      done_q <= 1'b1;
                      command_error_q <= 1'b1;
                    end
                  end
                  CMD_WRITE: begin
                    if (bus_owned_q) begin
                      busy_q <= 1'b1;
                      done_q <= 1'b0;
                      ack_error_q <= 1'b0;
                      command_error_q <= 1'b0;
                      bit_index_q <= 3'd0;
                      tx_shift_q <= tx_data_q;
                      state_q <= ST_WRITE_DRIVE;
                    end else begin
                      done_q <= 1'b1;
                      command_error_q <= 1'b1;
                    end
                  end
                  CMD_READ_ACK,
                  CMD_READ_NACK: begin
                    if (bus_owned_q) begin
                      busy_q <= 1'b1;
                      done_q <= 1'b0;
                      ack_error_q <= 1'b0;
                      command_error_q <= 1'b0;
                      bit_index_q <= 3'd0;
                      rx_shift_q <= 8'h00;
                      read_ack_q <= (write_data_i[4:0] == CMD_READ_ACK);
                      state_q <= ST_READ_DRIVE;
                    end else begin
                      done_q <= 1'b1;
                      command_error_q <= 1'b1;
                    end
                  end
                  default: begin
                    done_q <= 1'b1;
                    command_error_q <= 1'b1;
                  end
                endcase
              end
            end
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
