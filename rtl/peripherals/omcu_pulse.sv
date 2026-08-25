`default_nettype none

// Compact low-rate pulse/frequency engine. One of the three reviewed physical
// inputs is selected at a time, then crosses a dedicated two-flop
// synchronizer and a programmable N+1-sample digital stability filter. The
// selected channel owns a 16-bit wrapping edge count plus a 16-bit period in
// SYSCTRL run-tick units. Selecting a different physical input atomically
// clears the measurement epoch, so one result can never accidentally combine
// edges from two pins.
//
// This deliberately is not an asynchronous high-speed counter. It is for
// Hall, flow and other slow pulse sources whose electrical and sampling limits
// have been reviewed for the 27 MHz system clock.
module omcu_pulse (
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

  input  logic [31:0] run_ticks_i,
  input  logic [2:0]  pulse_i,
  output logic        irq_o
);

  localparam logic [5:0] REG_CTRL         = 6'h00;
  localparam logic [5:0] REG_INPUT_SELECT = 6'h01;
  localparam logic [5:0] REG_EDGE          = 6'h02;
  localparam logic [5:0] REG_FILTER        = 6'h03;
  localparam logic [5:0] REG_STATUS        = 6'h04;
  localparam logic [5:0] REG_CLEAR         = 6'h05;
  localparam logic [5:0] REG_COUNT         = 6'h06;
  localparam logic [5:0] REG_PERIOD        = 6'h07;
  localparam logic [5:0] REG_LAST_TICK     = 6'h08;

  logic        enable_q;
  logic        irq_enable_q;
  logic [1:0]  input_select_q;
  logic        falling_q;
  logic [7:0]  filter_q;
  logic        pulse_meta_q;
  logic        pulse_sync_q;
  logic        pulse_filtered_q;
  logic [7:0]  filter_count_q;
  logic        pending_q;
  logic        last_valid_q;
  logic [15:0] count_q;
  logic [15:0] period_q;
  logic [15:0] last_tick_q;

  logic        selected_pulse;
  logic        filter_accept;
  logic        pulse_filtered_next;
  logic        rise_event;
  logic        fall_event;
  logic        edge_event;
  logic        full_word_write;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = irq_enable_q && pending_q;
  // ABI-0.8 extension configuration is intentionally atomic. The SDK uses
  // aligned 32-bit stores; a partial store is ignored instead of producing a
  // torn input-selection or edge configuration.
  assign full_word_write = write_strobe_i == 4'b1111;

  always_comb begin
    selected_pulse = 1'b0;
    unique case (input_select_q)
      2'd0: selected_pulse = pulse_i[0];
      2'd1: selected_pulse = pulse_i[1];
      2'd2: selected_pulse = pulse_i[2];
      default: selected_pulse = 1'b0;
    endcase
  end

  assign filter_accept = (pulse_sync_q != pulse_filtered_q) &&
                         (filter_count_q == filter_q);
  assign pulse_filtered_next = filter_accept ? pulse_sync_q : pulse_filtered_q;
  assign rise_event = !pulse_filtered_q && pulse_filtered_next;
  assign fall_event = pulse_filtered_q && !pulse_filtered_next;
  assign edge_event = enable_q && (falling_q ? fall_event : rise_event);

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = irq_enable_q;

    status_read = '0;
    status_read[0] = pending_q;
    status_read[1] = pulse_filtered_q;
    status_read[2] = last_valid_q;
    status_read[5:4] = input_select_q;

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:         read_data_o = ctrl_read;
      REG_INPUT_SELECT: read_data_o = {30'h00000000, input_select_q};
      REG_EDGE:         read_data_o = {31'h00000000, falling_q};
      REG_FILTER:       read_data_o = {24'h000000, filter_q};
      REG_STATUS:       read_data_o = status_read;
      REG_COUNT:        read_data_o = {16'h0000, count_q};
      REG_PERIOD:       read_data_o = {16'h0000, period_q};
      REG_LAST_TICK:    read_data_o = {16'h0000, last_tick_q};
      default:           read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      input_select_q <= 2'd0;
      falling_q <= 1'b0;
      filter_q <= 8'h00;
      pulse_meta_q <= 1'b0;
      pulse_sync_q <= 1'b0;
      pulse_filtered_q <= 1'b0;
      filter_count_q <= 8'h00;
      pending_q <= 1'b0;
      last_valid_q <= 1'b0;
      count_q <= 16'h0000;
      period_q <= 16'h0000;
      last_tick_q <= 16'h0000;
    end else begin
      // No raw pulse_i signal is used below this synchronizer.
      pulse_meta_q <= selected_pulse;
      pulse_sync_q <= pulse_meta_q;

      if (pulse_sync_q == pulse_filtered_q) begin
        filter_count_q <= 8'h00;
      end else if (filter_accept) begin
        pulse_filtered_q <= pulse_filtered_next;
        filter_count_q <= 8'h00;
      end else begin
        filter_count_q <= filter_count_q + 8'd1;
      end

      if (edge_event) begin
        count_q <= count_q + 16'd1;
        period_q <= last_valid_q ? (run_ticks_i[15:0] - last_tick_q) : 16'h0000;
        last_tick_q <= run_ticks_i[15:0];
        last_valid_q <= 1'b1;
        pending_q <= 1'b1;
      end

      if (req_i && write_i && full_word_write) begin
        unique case (addr_i[7:2])
          REG_CTRL: begin
            enable_q <= write_data_i[0];
            irq_enable_q <= write_data_i[1];
          end
          REG_INPUT_SELECT: if (write_data_i[1:0] < 2'd3) begin
            // Configuration is an epoch boundary: a new pin starts with an
            // empty count and no valid period, even if it happened to have
            // the same logic level as the former selected pin.
            input_select_q <= write_data_i[1:0];
            pulse_filtered_q <= pulse_sync_q;
            filter_count_q <= 8'h00;
            pending_q <= 1'b0;
            last_valid_q <= 1'b0;
            count_q <= 16'h0000;
            period_q <= 16'h0000;
            last_tick_q <= 16'h0000;
          end
          REG_EDGE: falling_q <= write_data_i[0];
          REG_FILTER: begin
            filter_q <= write_data_i[7:0];
            filter_count_q <= 8'h00;
          end
          REG_STATUS:
            // W1C; a selected edge in this exact clock wins.
            pending_q <= (pending_q && !write_data_i[0]) || edge_event;
          REG_CLEAR: if (write_data_i[0] && !edge_event) begin
            pending_q <= 1'b0;
            last_valid_q <= 1'b0;
            count_q <= 16'h0000;
            period_q <= 16'h0000;
            last_tick_q <= 16'h0000;
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
