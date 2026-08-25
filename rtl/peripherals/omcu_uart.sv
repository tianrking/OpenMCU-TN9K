`default_nettype none

// Simple 8-N-1 UART0 for the portable OpenMCU MMIO contract. BAUDDIV is the
// number of system clocks per bit minus one. At 27 MHz, the reset value 233
// yields approximately 115.38 kbaud.
module omcu_uart #(
  parameter integer BAUDDIV_RESET = 233
) (
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

  input  logic        rx_i,
  output logic        tx_o,
  output logic        irq_o
);

  localparam logic [5:0] REG_DATA    = 6'h00;
  localparam logic [5:0] REG_STATUS  = 6'h01;
  localparam logic [5:0] REG_BAUDDIV = 6'h02;
  localparam logic [5:0] REG_CTRL    = 6'h03;

  localparam logic [1:0] RX_IDLE  = 2'd0;
  localparam logic [1:0] RX_START = 2'd1;
  localparam logic [1:0] RX_DATA  = 2'd2;
  localparam logic [1:0] RX_STOP  = 2'd3;

  logic        tx_enable_q;
  logic        rx_enable_q;
  logic        rx_irq_enable_q;
  logic [15:0] bauddiv_q;

  logic        tx_busy_q;
  logic [9:0]  tx_shift_q;
  logic [3:0]  tx_bits_remaining_q;
  logic [15:0] tx_counter_q;

  logic        rx_meta_q;
  logic        rx_sync_q;
  logic [1:0]  rx_state_q;
  logic [15:0] rx_counter_q;
  logic [2:0]  rx_bit_index_q;
  logic [7:0]  rx_shift_q;
  logic [7:0]  rx_data_q;
  logic        rx_valid_q;
  logic        rx_overrun_q;
  logic        rx_framing_error_q;

  logic [31:0] ctrl_read;
  logic [31:0] status_read;
  logic [15:0] rx_start_counter_load;
  logic        full_word_write;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign tx_o = tx_busy_q ? tx_shift_q[0] : 1'b1;
  assign irq_o = rx_valid_q && rx_irq_enable_q;
  // All UART control/data commands use aligned 32-bit SDK stores.  Reject
  // partial writes to keep BAUDDIV/CTRL updates atomic and compact in LUTs.
  assign full_word_write = write_strobe_i == 4'b1111;

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = tx_enable_q;
    ctrl_read[1] = rx_enable_q;
    ctrl_read[2] = rx_irq_enable_q;

    status_read = '0;
    status_read[0] = tx_enable_q && !tx_busy_q;
    status_read[1] = rx_valid_q;
    status_read[2] = rx_overrun_q;
    status_read[3] = rx_framing_error_q;
    status_read[4] = tx_busy_q;

    // RX_START is entered after the two-flop synchronizer has already added
    // latency. Compensate the half-bit wait so normal baud divisors sample
    // near the centre of the actual start bit. Tiny divisors saturate safely.
    if (bauddiv_q < 16'd4) begin
      rx_start_counter_load = 16'h0000;
    end else begin
      rx_start_counter_load = (bauddiv_q >> 1) - 16'd2;
    end
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_DATA:    read_data_o = {24'h000000, rx_data_q};
      REG_STATUS:  read_data_o = status_read;
      REG_BAUDDIV: read_data_o = {16'h0000, bauddiv_q};
      REG_CTRL:    read_data_o = ctrl_read;
      default:     read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      tx_enable_q <= 1'b0;
      rx_enable_q <= 1'b0;
      rx_irq_enable_q <= 1'b0;
      bauddiv_q <= BAUDDIV_RESET[15:0];

      tx_busy_q <= 1'b0;
      tx_shift_q <= 10'h3ff;
      tx_bits_remaining_q <= 4'd0;
      tx_counter_q <= 16'h0000;

      rx_meta_q <= 1'b1;
      rx_sync_q <= 1'b1;
      rx_state_q <= RX_IDLE;
      rx_counter_q <= 16'h0000;
      rx_bit_index_q <= 3'd0;
      rx_shift_q <= 8'h00;
      rx_data_q <= 8'h00;
      rx_valid_q <= 1'b0;
      rx_overrun_q <= 1'b0;
      rx_framing_error_q <= 1'b0;
    end else begin
      // Two-stage input synchronizer; the receiver assumes a common system
      // clock and has no hidden asynchronous state.
      rx_meta_q <= rx_i;
      rx_sync_q <= rx_meta_q;

      if (tx_busy_q) begin
        if (tx_counter_q == bauddiv_q) begin
          tx_counter_q <= 16'h0000;
          if (tx_bits_remaining_q == 4'd1) begin
            tx_busy_q <= 1'b0;
            tx_bits_remaining_q <= 4'd0;
          end else begin
            tx_shift_q <= {1'b1, tx_shift_q[9:1]};
            tx_bits_remaining_q <= tx_bits_remaining_q - 4'd1;
          end
        end else begin
          tx_counter_q <= tx_counter_q + 16'd1;
        end
      end

      if (!rx_enable_q) begin
        rx_state_q <= RX_IDLE;
        rx_counter_q <= 16'h0000;
      end else begin
        unique case (rx_state_q)
          RX_IDLE: begin
            if (!rx_sync_q) begin
              // Confirm the start bit half a bit after observing the edge.
              rx_state_q <= RX_START;
              rx_counter_q <= rx_start_counter_load;
            end
          end
          RX_START: begin
            if (rx_counter_q == 16'h0000) begin
              if (!rx_sync_q) begin
                rx_state_q <= RX_DATA;
                rx_counter_q <= bauddiv_q;
                rx_bit_index_q <= 3'd0;
              end else begin
                rx_state_q <= RX_IDLE;
              end
            end else begin
              rx_counter_q <= rx_counter_q - 16'd1;
            end
          end
          RX_DATA: begin
            if (rx_counter_q == 16'h0000) begin
              rx_shift_q[rx_bit_index_q] <= rx_sync_q;
              rx_counter_q <= bauddiv_q;
              if (rx_bit_index_q == 3'd7) begin
                rx_state_q <= RX_STOP;
              end else begin
                rx_bit_index_q <= rx_bit_index_q + 3'd1;
              end
            end else begin
              rx_counter_q <= rx_counter_q - 16'd1;
            end
          end
          RX_STOP: begin
            if (rx_counter_q == 16'h0000) begin
              rx_state_q <= RX_IDLE;
              if (rx_sync_q) begin
                if (rx_valid_q) begin
                  rx_overrun_q <= 1'b1;
                end else begin
                  rx_data_q <= rx_shift_q;
                  rx_valid_q <= 1'b1;
                end
              end else begin
                rx_framing_error_q <= 1'b1;
              end
            end else begin
              rx_counter_q <= rx_counter_q - 16'd1;
            end
          end
          default: begin
            rx_state_q <= RX_IDLE;
          end
        endcase
      end

      if (req_i && write_i && full_word_write) begin
        unique case (addr_i[7:2])
          REG_DATA: begin
            if (tx_enable_q && !tx_busy_q) begin
              tx_busy_q <= 1'b1;
              tx_shift_q <= {1'b1, write_data_i[7:0], 1'b0};
              tx_bits_remaining_q <= 4'd10;
              tx_counter_q <= 16'h0000;
            end
          end
          REG_STATUS: begin
            if (write_data_i[2]) begin
              rx_overrun_q <= 1'b0;
            end
            if (write_data_i[3]) begin
              rx_framing_error_q <= 1'b0;
            end
          end
          REG_BAUDDIV: begin
            bauddiv_q <= write_data_i[15:0];
          end
          REG_CTRL: begin
            tx_enable_q <= write_data_i[0];
            rx_enable_q <= write_data_i[1];
            rx_irq_enable_q <= write_data_i[2];
          end
          default: begin
          end
        endcase
      end

      if (req_i && !write_i && (addr_i[7:2] == REG_DATA)) begin
        rx_valid_q <= 1'b0;
      end
    end
  end

endmodule

`default_nettype wire
