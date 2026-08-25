`default_nettype none

// Two independent hardware compare alarms sharing TIMER0's established
// prescaled tick. Both comparators are evaluated on every TIMER0 tick, so
// channel 0 and channel 1 can fire in the same tick with no scan latency.
//
// Keeping one physical timebase is intentional: it makes TIMER0 the single
// authority for start/stop, prescale and wrap while ALARM0 contributes the
// extra independent deadlines. The compact Tang Nano 9K profile compares the
// low 16 bits of TIMER0.COUNT; software should schedule relative deadlines
// and treat the resulting 16-bit wrap in the usual modular-timer manner.
module omcu_alarm (
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

  // TIMER0 observation ports. ALARM0 never writes these values.
  input  logic [15:0] timebase_count_i,
  input  logic [15:0] timebase_prescale_i,
  input  logic        timebase_enable_i,
  input  logic        timebase_tick_i,

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

  logic        enable_q;
  logic [1:0]  channel_enable_q;
  logic [1:0]  irq_enable_q;
  logic [1:0]  periodic_q;
  logic [1:0]  pending_q;
  logic [15:0] compare0_q;
  logic [15:0] compare1_q;
  logic [15:0] period0_q;
  logic [15:0] period1_q;

  logic        timebase_tick;
  logic        compare0_event;
  logic        compare1_event;
  logic [15:0] compare0_advanced;
  logic [15:0] compare1_advanced;
  logic        full_word_write;
  logic [31:0] ctrl_read;
  logic [31:0] channel_enable_read;
  logic [31:0] irq_enable_read;
  logic [31:0] periodic_read;
  logic [31:0] pending_read;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = |(pending_q & irq_enable_q);
  // ALARM0.CTRL only gates its comparators; TIMER0 itself keeps running for
  // legacy software and any other consumer of the timebase.
  assign timebase_tick = enable_q && timebase_enable_i && timebase_tick_i;
  // Equality, rather than >=, preserves periodic phase across the natural
  // 16-bit wrap. SDK helpers schedule relative to COUNT to avoid an already
  // passed absolute deadline.
  assign compare0_event = timebase_tick && channel_enable_q[0] &&
                          (timebase_count_i == compare0_q);
  assign compare1_event = timebase_tick && channel_enable_q[1] &&
                          (timebase_count_i == compare1_q);
  assign compare0_advanced = compare0_q + period0_q;
  assign compare1_advanced = compare1_q + period1_q;
  // Extension-page writes are atomic: the SDK uses full 32-bit MMIO stores;
  // byte/halfword writes are deliberately ignored instead of tearing a timer
  // configuration while it is live.
  assign full_word_write = write_strobe_i == 4'b1111;

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = timebase_enable_i;
    channel_enable_read = '0;
    irq_enable_read = '0;
    periodic_read = '0;
    pending_read = '0;
    channel_enable_read[1:0] = channel_enable_q;
    irq_enable_read[1:0] = irq_enable_q;
    periodic_read[1:0] = periodic_q;
    pending_read[1:0] = pending_q;

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:           read_data_o = ctrl_read;
      // TIMER0 owns these two values. They are retained as read-only mirrors
      // at ALARM0 so the two-alarm API can calculate relative deadlines
      // without a second MMIO page read.
      REG_PRESCALE:       read_data_o = {16'h0000, timebase_prescale_i};
      REG_COUNT:          read_data_o = {16'h0000, timebase_count_i};
      REG_CHANNEL_ENABLE: read_data_o = channel_enable_read;
      REG_IRQ_ENABLE:     read_data_o = irq_enable_read;
      REG_PERIODIC:       read_data_o = periodic_read;
      REG_PENDING:        read_data_o = pending_read;
      REG_COMPARE0:       read_data_o = {16'h0000, compare0_q};
      REG_COMPARE1:       read_data_o = {16'h0000, compare1_q};
      REG_PERIOD0:        read_data_o = {16'h0000, period0_q};
      REG_PERIOD1:        read_data_o = {16'h0000, period1_q};
      // Kept as reserved read-zero slots so the ABI page remains naturally
      // laid out. This physically fitted profile implements channels 0 and 1.
      REG_COMPARE2,
      REG_COMPARE3,
      REG_PERIOD2,
      REG_PERIOD3:        read_data_o = 32'h0000_0000;
      default:             read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      channel_enable_q <= 2'b00;
      irq_enable_q <= 2'b00;
      periodic_q <= 2'b00;
      pending_q <= 2'b00;
      compare0_q <= 16'hffff;
      compare1_q <= 16'hffff;
      period0_q <= 16'h0000;
      period1_q <= 16'h0000;
    end else begin
      pending_q <= pending_q | {compare1_event, compare0_event};
      if (compare0_event) begin
        if (periodic_q[0] && (period0_q != 16'h0000)) begin
          compare0_q <= compare0_advanced;
        end else begin
          // A zero period behaves safely as a one-shot instead of refiring
          // on every timebase tick or counter wrap.
          channel_enable_q[0] <= 1'b0;
        end
      end
      if (compare1_event) begin
        if (periodic_q[1] && (period1_q != 16'h0000)) begin
          compare1_q <= compare1_advanced;
        end else begin
          channel_enable_q[1] <= 1'b0;
        end
      end

      if (req_i && write_i && full_word_write) begin
        unique case (addr_i[7:2])
          REG_CTRL:           enable_q <= write_data_i[0];
          // PRESCALE and COUNT are TIMER0 read-only mirrors in this page.
          REG_CHANNEL_ENABLE: channel_enable_q <= write_data_i[1:0];
          REG_IRQ_ENABLE:     irq_enable_q <= write_data_i[1:0];
          REG_PERIODIC:       periodic_q <= write_data_i[1:0];
          REG_PENDING:
            // W1C, while a matching comparator event in this clock wins.
            pending_q <= (pending_q & ~write_data_i[1:0]) |
                         {compare1_event, compare0_event};
          REG_COMPARE0:       compare0_q <= write_data_i[15:0];
          REG_COMPARE1:       compare1_q <= write_data_i[15:0];
          REG_PERIOD0:        period0_q <= write_data_i[15:0];
          REG_PERIOD1:        period1_q <= write_data_i[15:0];
          default: begin
            // Reserved channel-2/3 registers and TIMER0 mirror registers
            // are ignored on write.
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
