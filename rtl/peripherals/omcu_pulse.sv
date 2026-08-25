`default_nettype none

// Three low-rate pulse/frequency inputs.  Each channel owns a two-flop input
// synchronizer, a shared configurable digital stability filter, a wrapping
// 32-bit edge count and a measured period in SYSCTRL run-tick units.  This is
// intentionally not an asynchronous high-speed counter: board-level signals
// must satisfy the 27 MHz synchronous sampling and input-electrical limits.
module omcu_pulse #(
  parameter integer PULSE_COUNT = 3
) (
  input  logic                     clk_i,
  input  logic                     rst_ni,

  input  logic                     req_i,
  input  logic                     write_i,
  input  logic [31:0]              addr_i,
  input  logic [31:0]              write_data_i,
  input  logic [3:0]               write_strobe_i,
  output logic                     ready_o,
  output logic [31:0]              read_data_o,
  output logic                     error_o,

  input  logic [31:0]              run_ticks_i,
  input  logic [PULSE_COUNT-1:0]   pulse_i,
  output logic                     irq_o
);

  localparam logic [5:0] REG_CTRL           = 6'h00;
  localparam logic [5:0] REG_CHANNEL_ENABLE = 6'h01;
  localparam logic [5:0] REG_FALLING        = 6'h02;
  localparam logic [5:0] REG_FILTER          = 6'h03;
  localparam logic [5:0] REG_STATUS          = 6'h04;
  localparam logic [5:0] REG_CLEAR           = 6'h05;
  localparam logic [5:0] REG_COUNT0          = 6'h06;
  localparam logic [5:0] REG_COUNT1          = 6'h07;
  localparam logic [5:0] REG_COUNT2          = 6'h08;
  localparam logic [5:0] REG_PERIOD0         = 6'h09;
  localparam logic [5:0] REG_PERIOD1         = 6'h0a;
  localparam logic [5:0] REG_PERIOD2         = 6'h0b;
  localparam logic [5:0] REG_LAST_TICK0      = 6'h0c;
  localparam logic [5:0] REG_LAST_TICK1      = 6'h0d;
  localparam logic [5:0] REG_LAST_TICK2      = 6'h0e;

  logic enable_q;
  logic irq_enable_q;
  logic [PULSE_COUNT-1:0] channel_enable_q;
  logic [PULSE_COUNT-1:0] falling_q;
  logic [7:0] filter_q;
  logic [PULSE_COUNT-1:0] pulse_meta_q;
  logic [PULSE_COUNT-1:0] pulse_sync_q;
  logic [PULSE_COUNT-1:0] pulse_filtered_q;
  logic [PULSE_COUNT*8-1:0] filter_count_q;
  logic [PULSE_COUNT-1:0] pulse_filtered_next;
  logic [PULSE_COUNT-1:0] rise_events;
  logic [PULSE_COUNT-1:0] fall_events;
  logic [PULSE_COUNT-1:0] edge_events;
  logic [PULSE_COUNT-1:0] pending_q;
  logic [PULSE_COUNT-1:0] last_valid_q;
  logic [31:0] count_q [0:PULSE_COUNT-1];
  logic [31:0] period_q [0:PULSE_COUNT-1];
  logic [31:0] last_tick_q [0:PULSE_COUNT-1];
  logic [31:0] ctrl_read;
  logic [31:0] channel_enable_read;
  logic [31:0] falling_read;
  logic [31:0] status_read;
  logic [31:0] channel_enable_merged;
  logic [31:0] falling_merged;
  logic [31:0] write_masked_data;
  integer pulse_index;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = irq_enable_q && (|pending_q);
  assign write_masked_data = write_data_i & `OMCU_WRITE_STROBE_MASK(write_strobe_i);
  assign channel_enable_merged = `OMCU_MERGE_WRITE(
    channel_enable_read, write_data_i, write_strobe_i
  );
  assign falling_merged = `OMCU_MERGE_WRITE(falling_read, write_data_i, write_strobe_i);

  always_comb begin
    pulse_filtered_next = pulse_filtered_q;
    for (pulse_index = 0; pulse_index < PULSE_COUNT; pulse_index = pulse_index + 1) begin
      if ((pulse_sync_q[pulse_index] != pulse_filtered_q[pulse_index]) &&
          (filter_count_q[pulse_index * 8 +: 8] == filter_q)) begin
        pulse_filtered_next[pulse_index] = pulse_sync_q[pulse_index];
      end
    end
  end

  assign rise_events = ~pulse_filtered_q & pulse_filtered_next;
  assign fall_events = pulse_filtered_q & ~pulse_filtered_next;
  assign edge_events = {PULSE_COUNT{enable_q}} & channel_enable_q &
                       ((rise_events & ~falling_q) | (fall_events & falling_q));

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = irq_enable_q;
    channel_enable_read = '0;
    falling_read = '0;
    status_read = '0;
    channel_enable_read[PULSE_COUNT-1:0] = channel_enable_q;
    falling_read[PULSE_COUNT-1:0] = falling_q;
    status_read[PULSE_COUNT-1:0] = pending_q;
    status_read[8 +: PULSE_COUNT] = pulse_filtered_q;
    status_read[16 +: PULSE_COUNT] = last_valid_q;

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:           read_data_o = ctrl_read;
      REG_CHANNEL_ENABLE: read_data_o = channel_enable_read;
      REG_FALLING:        read_data_o = falling_read;
      REG_FILTER:         read_data_o = {24'h000000, filter_q};
      REG_STATUS:         read_data_o = status_read;
      REG_COUNT0:         read_data_o = count_q[0];
      REG_COUNT1:         read_data_o = count_q[1];
      REG_COUNT2:         read_data_o = count_q[2];
      REG_PERIOD0:        read_data_o = period_q[0];
      REG_PERIOD1:        read_data_o = period_q[1];
      REG_PERIOD2:        read_data_o = period_q[2];
      REG_LAST_TICK0:     read_data_o = last_tick_q[0];
      REG_LAST_TICK1:     read_data_o = last_tick_q[1];
      REG_LAST_TICK2:     read_data_o = last_tick_q[2];
      default:             read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      channel_enable_q <= '0;
      falling_q <= '0;
      filter_q <= 8'h00;
      pulse_meta_q <= '0;
      pulse_sync_q <= '0;
      pulse_filtered_q <= '0;
      filter_count_q <= '0;
      pending_q <= '0;
      last_valid_q <= '0;
      for (pulse_index = 0; pulse_index < PULSE_COUNT; pulse_index = pulse_index + 1) begin
        count_q[pulse_index] <= 32'h0000_0000;
        period_q[pulse_index] <= 32'h0000_0000;
        last_tick_q[pulse_index] <= 32'h0000_0000;
      end
    end else begin
      // Never use raw pulse_i below this two-flop synchronizer.
      pulse_meta_q <= pulse_i;
      pulse_sync_q <= pulse_meta_q;
      for (pulse_index = 0; pulse_index < PULSE_COUNT; pulse_index = pulse_index + 1) begin
        if (pulse_sync_q[pulse_index] == pulse_filtered_q[pulse_index]) begin
          filter_count_q[pulse_index * 8 +: 8] <= 8'h00;
        end else if (pulse_filtered_next[pulse_index] != pulse_filtered_q[pulse_index]) begin
          pulse_filtered_q[pulse_index] <= pulse_filtered_next[pulse_index];
          filter_count_q[pulse_index * 8 +: 8] <= 8'h00;
        end else begin
          filter_count_q[pulse_index * 8 +: 8] <=
            filter_count_q[pulse_index * 8 +: 8] + 8'd1;
        end

        if (edge_events[pulse_index]) begin
          count_q[pulse_index] <= count_q[pulse_index] + 32'd1;
          if (last_valid_q[pulse_index]) begin
            period_q[pulse_index] <= run_ticks_i - last_tick_q[pulse_index];
          end else begin
            period_q[pulse_index] <= 32'h0000_0000;
          end
          last_tick_q[pulse_index] <= run_ticks_i;
          last_valid_q[pulse_index] <= 1'b1;
        end
      end
      pending_q <= pending_q | edge_events;

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: if (write_strobe_i[0]) begin
            enable_q <= write_data_i[0];
            irq_enable_q <= write_data_i[1];
          end
          REG_CHANNEL_ENABLE:
            channel_enable_q <= channel_enable_merged[PULSE_COUNT-1:0];
          REG_FALLING:
            falling_q <= falling_merged[PULSE_COUNT-1:0];
          REG_FILTER: if (write_strobe_i[0]) begin
            filter_q <= write_data_i[7:0];
            filter_count_q <= '0;
          end
          REG_STATUS:
            // W1C while an edge in this clock always wins.
            pending_q <= (pending_q & ~write_masked_data[PULSE_COUNT-1:0]) |
                         edge_events;
          REG_CLEAR: begin
            // CLEAR resets one channel's accumulated measurements. If a new
            // selected edge arrives in this exact cycle, that event wins and
            // becomes the first sample of the new measurement epoch.
            for (pulse_index = 0; pulse_index < PULSE_COUNT; pulse_index = pulse_index + 1) begin
              if (write_masked_data[pulse_index]) begin
                if (edge_events[pulse_index]) begin
                  count_q[pulse_index] <= count_q[pulse_index] + 32'd1;
                  period_q[pulse_index] <= last_valid_q[pulse_index] ?
                    (run_ticks_i - last_tick_q[pulse_index]) : 32'h0000_0000;
                  last_tick_q[pulse_index] <= run_ticks_i;
                  last_valid_q[pulse_index] <= 1'b1;
                  pending_q[pulse_index] <= 1'b1;
                end else begin
                  count_q[pulse_index] <= 32'h0000_0000;
                  period_q[pulse_index] <= 32'h0000_0000;
                  last_tick_q[pulse_index] <= 32'h0000_0000;
                  last_valid_q[pulse_index] <= 1'b0;
                  pending_q[pulse_index] <= 1'b0;
                end
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
