`default_nettype none

// Four independent compare channels sharing one 32-bit prescaled timebase.
// A periodic channel advances only its own next compare value, so it does not
// reset or disturb the other channels. This complements the legacy TIMER0
// one-shot/auto-reload contract instead of changing it underneath existing
// firmware.
module omcu_alarm #(
  parameter integer CHANNEL_COUNT = 4
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

  output logic        irq_o
);

  localparam logic [5:0] REG_CTRL           = 6'h00;
  localparam logic [5:0] REG_PRESCALE       = 6'h01;
  localparam logic [5:0] REG_COUNT          = 6'h02;
  localparam logic [5:0] REG_CHANNEL_ENABLE = 6'h03;
  localparam logic [5:0] REG_IRQ_ENABLE     = 6'h04;
  localparam logic [5:0] REG_PERIODIC       = 6'h05;
  localparam logic [5:0] REG_PENDING        = 6'h06;
  localparam logic [5:0] REG_COMPARE0       = 6'h07;
  localparam logic [5:0] REG_COMPARE1       = 6'h08;
  localparam logic [5:0] REG_COMPARE2       = 6'h09;
  localparam logic [5:0] REG_COMPARE3       = 6'h0a;
  localparam logic [5:0] REG_PERIOD0        = 6'h0b;
  localparam logic [5:0] REG_PERIOD1        = 6'h0c;
  localparam logic [5:0] REG_PERIOD2        = 6'h0d;
  localparam logic [5:0] REG_PERIOD3        = 6'h0e;

  logic enable_q;
  logic [15:0] prescale_q;
  logic [15:0] prescale_count_q;
  logic [31:0] count_q;
  logic [CHANNEL_COUNT-1:0] channel_enable_q;
  logic [CHANNEL_COUNT-1:0] irq_enable_q;
  logic [CHANNEL_COUNT-1:0] periodic_q;
  logic [CHANNEL_COUNT-1:0] pending_q;
  logic [31:0] compare_q [0:CHANNEL_COUNT-1];
  logic [31:0] period_q [0:CHANNEL_COUNT-1];
  logic [CHANNEL_COUNT-1:0] compare_events;
  logic counter_tick;
  logic [31:0] prescale_merged;
  logic [31:0] channel_enable_merged;
  logic [31:0] irq_enable_merged;
  logic [31:0] periodic_merged;
  logic [31:0] write_masked_data;
  logic [31:0] ctrl_read;
  logic [31:0] channel_enable_read;
  logic [31:0] irq_enable_read;
  logic [31:0] periodic_read;
  logic [31:0] pending_read;
  integer channel_index;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = |(pending_q & irq_enable_q);
  assign counter_tick = enable_q && (prescale_count_q == prescale_q);
  assign prescale_merged = `OMCU_MERGE_WRITE(
    {16'h0000, prescale_q}, write_data_i, write_strobe_i
  );
  assign channel_enable_merged = `OMCU_MERGE_WRITE(
    channel_enable_read, write_data_i, write_strobe_i
  );
  assign irq_enable_merged = `OMCU_MERGE_WRITE(
    irq_enable_read, write_data_i, write_strobe_i
  );
  assign periodic_merged = `OMCU_MERGE_WRITE(
    periodic_read, write_data_i, write_strobe_i
  );
  assign write_masked_data = write_data_i & `OMCU_WRITE_STROBE_MASK(write_strobe_i);

  always_comb begin
    compare_events = '0;
    for (channel_index = 0;
         channel_index < CHANNEL_COUNT;
         channel_index = channel_index + 1) begin
      compare_events[channel_index] = counter_tick &&
                                      channel_enable_q[channel_index] &&
                                      (count_q == compare_q[channel_index]);
    end
  end

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    channel_enable_read = '0;
    irq_enable_read = '0;
    periodic_read = '0;
    pending_read = '0;
    channel_enable_read[CHANNEL_COUNT-1:0] = channel_enable_q;
    irq_enable_read[CHANNEL_COUNT-1:0] = irq_enable_q;
    periodic_read[CHANNEL_COUNT-1:0] = periodic_q;
    pending_read[CHANNEL_COUNT-1:0] = pending_q;

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:           read_data_o = ctrl_read;
      REG_PRESCALE:       read_data_o = {16'h0000, prescale_q};
      REG_COUNT:          read_data_o = count_q;
      REG_CHANNEL_ENABLE: read_data_o = channel_enable_read;
      REG_IRQ_ENABLE:     read_data_o = irq_enable_read;
      REG_PERIODIC:       read_data_o = periodic_read;
      REG_PENDING:        read_data_o = pending_read;
      REG_COMPARE0:       read_data_o = compare_q[0];
      REG_COMPARE1:       read_data_o = compare_q[1];
      REG_COMPARE2:       read_data_o = compare_q[2];
      REG_COMPARE3:       read_data_o = compare_q[3];
      REG_PERIOD0:        read_data_o = period_q[0];
      REG_PERIOD1:        read_data_o = period_q[1];
      REG_PERIOD2:        read_data_o = period_q[2];
      REG_PERIOD3:        read_data_o = period_q[3];
      default:             read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      prescale_q <= 16'h0000;
      prescale_count_q <= 16'h0000;
      count_q <= 32'h0000_0000;
      channel_enable_q <= '0;
      irq_enable_q <= '0;
      periodic_q <= '0;
      pending_q <= '0;
      for (channel_index = 0;
           channel_index < CHANNEL_COUNT;
           channel_index = channel_index + 1) begin
        compare_q[channel_index] <= 32'hffff_ffff;
        period_q[channel_index] <= 32'h0000_0000;
      end
    end else begin
      if (enable_q) begin
        if (counter_tick) begin
          prescale_count_q <= 16'h0000;
          count_q <= count_q + 32'd1;
        end else begin
          prescale_count_q <= prescale_count_q + 16'd1;
        end
      end else begin
        prescale_count_q <= 16'h0000;
      end

      pending_q <= pending_q | compare_events;
      for (channel_index = 0;
           channel_index < CHANNEL_COUNT;
           channel_index = channel_index + 1) begin
        if (compare_events[channel_index]) begin
          if (periodic_q[channel_index] && (period_q[channel_index] != 32'h0000_0000)) begin
            compare_q[channel_index] <= compare_q[channel_index] + period_q[channel_index];
          end else begin
            // A zero period is deliberately safe: it behaves as a one-shot
            // rather than repeatedly firing every counter wrap.
            channel_enable_q[channel_index] <= 1'b0;
          end
        end
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: if (write_strobe_i[0]) begin
            enable_q <= write_data_i[0];
            if (!write_data_i[0]) begin
              prescale_count_q <= 16'h0000;
            end
          end
          REG_PRESCALE: prescale_q <= prescale_merged[15:0];
          REG_COUNT: count_q <= `OMCU_MERGE_WRITE(count_q, write_data_i, write_strobe_i);
          REG_CHANNEL_ENABLE:
            channel_enable_q <= channel_enable_merged[CHANNEL_COUNT-1:0];
          REG_IRQ_ENABLE:
            irq_enable_q <= irq_enable_merged[CHANNEL_COUNT-1:0];
          REG_PERIODIC:
            periodic_q <= periodic_merged[CHANNEL_COUNT-1:0];
          REG_PENDING:
            // W1C, while a matching comparator event in this clock wins.
            pending_q <= (pending_q & ~write_masked_data[CHANNEL_COUNT-1:0]) |
                         compare_events;
          REG_COMPARE0:
            compare_q[0] <= `OMCU_MERGE_WRITE(compare_q[0], write_data_i, write_strobe_i);
          REG_COMPARE1:
            compare_q[1] <= `OMCU_MERGE_WRITE(compare_q[1], write_data_i, write_strobe_i);
          REG_COMPARE2:
            compare_q[2] <= `OMCU_MERGE_WRITE(compare_q[2], write_data_i, write_strobe_i);
          REG_COMPARE3:
            compare_q[3] <= `OMCU_MERGE_WRITE(compare_q[3], write_data_i, write_strobe_i);
          REG_PERIOD0:
            period_q[0] <= `OMCU_MERGE_WRITE(period_q[0], write_data_i, write_strobe_i);
          REG_PERIOD1:
            period_q[1] <= `OMCU_MERGE_WRITE(period_q[1], write_data_i, write_strobe_i);
          REG_PERIOD2:
            period_q[2] <= `OMCU_MERGE_WRITE(period_q[2], write_data_i, write_strobe_i);
          REG_PERIOD3:
            period_q[3] <= `OMCU_MERGE_WRITE(period_q[3], write_data_i, write_strobe_i);
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
