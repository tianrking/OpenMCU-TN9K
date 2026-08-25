`default_nettype none

// Portable GPIO block for the OpenMCU single-master MMIO contract.
//
// Every input first crosses a two-flop synchronizer, then passes through one
// programmable shared stability filter before it reaches GPIO.IN, edge
// detection, GPIO IRQ status, or the event snapshot. FILTER_CYCLES=N requires
// N+1 unchanged synchronized samples across the whole GPIO port; N=0 bypasses
// the extra settling delay. A change on any input restarts that shared window,
// which trades documented cross-channel latency for far less LUT cost than a
// counter on every pin.
// This is deliberately a clock-domain-local slow-input conditioner, not an
// asynchronous high-speed capture path.
module omcu_gpio #(
  parameter integer GPIO_COUNT = 24
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic                  req_i,
  input  logic                  write_i,
  input  logic [31:0]           addr_i,
  input  logic [31:0]           write_data_i,
  input  logic [3:0]            write_strobe_i,
  output logic                  ready_o,
  output logic [31:0]           read_data_o,
  output logic                  error_o,

  // Snapshot context is supplied by the portable fabric. RUN_TICKS is the
  // low word of SYSCTRL's counter, and wraps naturally after 2^32 clocks.
  input  logic [31:0]           run_ticks_i,
  input  logic [31:0]           irq_active_i,
  input  logic [31:0]           reset_cause_i,
  // A reviewed hardware interlock may force a context capture even when the
  // software GPIO snapshot engine is disabled. A forced capture has priority
  // over an older normal snapshot and is marked in SNAPSHOT_STATUS.FORCED.
  input  logic                  snapshot_force_i,
  output logic [31:0]           snapshot_tick_o,
  output logic [31:0]           snapshot_gpio_o,
  output logic [31:0]           snapshot_irq_o,
  output logic [31:0]           snapshot_reset_o,

  input  logic [GPIO_COUNT-1:0] gpio_in_i,
  output logic [GPIO_COUNT-1:0] gpio_out_o,
  output logic [GPIO_COUNT-1:0] gpio_oe_o,
  output logic                  irq_o
);

  localparam logic [5:0] REG_OUT               = 6'h00;
  localparam logic [5:0] REG_OUT_SET           = 6'h01;
  localparam logic [5:0] REG_OUT_CLR           = 6'h02;
  localparam logic [5:0] REG_OUT_XOR           = 6'h03;
  localparam logic [5:0] REG_OE                = 6'h04;
  localparam logic [5:0] REG_OE_SET            = 6'h05;
  localparam logic [5:0] REG_OE_CLR            = 6'h06;
  localparam logic [5:0] REG_IN                = 6'h08;
  localparam logic [5:0] REG_RISE_EN           = 6'h09;
  localparam logic [5:0] REG_FALL_EN           = 6'h0a;
  localparam logic [5:0] REG_IRQ_STATUS        = 6'h0b;
  localparam logic [5:0] REG_FILTER_MASK       = 6'h0c;
  localparam logic [5:0] REG_FILTER_CYCLES     = 6'h0d;
  localparam logic [5:0] REG_SNAPSHOT_CTRL     = 6'h0e;
  localparam logic [5:0] REG_SNAPSHOT_RISE_EN  = 6'h0f;
  localparam logic [5:0] REG_SNAPSHOT_FALL_EN  = 6'h10;
  localparam logic [5:0] REG_SNAPSHOT_STATUS   = 6'h11;
  localparam logic [5:0] REG_SNAPSHOT_EVENT    = 6'h12;
  localparam logic [5:0] REG_SNAPSHOT_INPUT    = 6'h13;
  localparam logic [5:0] REG_SNAPSHOT_IRQ      = 6'h14;
  localparam logic [5:0] REG_SNAPSHOT_RESET    = 6'h15;
  localparam logic [5:0] REG_SNAPSHOT_TICKS    = 6'h16;

  logic [GPIO_COUNT-1:0] gpio_out_q;
  logic [GPIO_COUNT-1:0] gpio_oe_q;
  logic [GPIO_COUNT-1:0] gpio_meta_q;
  logic [GPIO_COUNT-1:0] gpio_sync_q;
  logic [GPIO_COUNT-1:0] gpio_filtered_q;
  logic [GPIO_COUNT-1:0] gpio_filter_sample_q;
  logic [7:0] filter_stable_count_q;
  logic [GPIO_COUNT-1:0] gpio_in_previous_q;
  logic [GPIO_COUNT-1:0] rise_enable_q;
  logic [GPIO_COUNT-1:0] fall_enable_q;
  logic [GPIO_COUNT-1:0] irq_status_q;
  logic [7:0] filter_cycles_q;

  logic snapshot_enable_q;
  logic snapshot_irq_enable_q;
  logic snapshot_overwrite_q;
  logic snapshot_valid_q;
  logic snapshot_overflow_q;
  logic snapshot_forced_q;
  logic [GPIO_COUNT-1:0] snapshot_event_q;
  logic [GPIO_COUNT-1:0] snapshot_input_q;
  // The portable fabric only exposes external IRQ sources in CPU bits 8..18
  // and the reset sequencer only has three one-hot causes. Keep the retained
  // state at that true information width, then zero-extend it at the 32-bit
  // ABI registers.
  logic [10:0] snapshot_irq_q;
  logic [2:0] snapshot_reset_q;
  logic [31:0] snapshot_ticks_q;

  logic [GPIO_COUNT-1:0] gpio_sampled;
  logic [GPIO_COUNT-1:0] rise_events;
  logic [GPIO_COUNT-1:0] fall_events;
  logic [GPIO_COUNT-1:0] irq_events;
  logic [GPIO_COUNT-1:0] snapshot_events;
  logic snapshot_normal_event;
  logic snapshot_capture_event;
  logic snapshot_overflow_event;
  logic filtered_input_changed;
  logic filter_settled;

  logic [31:0] gpio_out_ext;
  logic [31:0] gpio_oe_ext;
  logic [31:0] gpio_in_ext;
  logic [31:0] rise_enable_ext;
  logic [31:0] fall_enable_ext;
  logic [31:0] irq_status_ext;
  logic [31:0] filter_scope_ext;
  logic [31:0] snapshot_event_ext;
  logic [31:0] snapshot_input_ext;
  logic        full_word_write;
  logic [31:0] snapshot_ctrl_read;
  logic [31:0] snapshot_status_read;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign gpio_out_o = gpio_out_q;
  assign gpio_oe_o = gpio_oe_q;
  // Snapshot completion intentionally shares the established GPIO0 CPU IRQ.
  // Existing GPIO-only firmware is unaffected unless SNAPSHOT.IRQ_ENABLE is
  // explicitly set.
  assign irq_o = (|irq_status_q) ||
                 (snapshot_valid_q && snapshot_irq_enable_q);
  assign snapshot_tick_o = snapshot_ticks_q;
  assign snapshot_irq_o = {13'h0000, snapshot_irq_q, 8'h00};
  assign snapshot_reset_o = {29'h00000000, snapshot_reset_q};
  // GPIO masks and snapshot control are 32-bit ABI registers.  Require one
  // full store so edge enables and pad ownership never observe a torn mask;
  // this also avoids four wide byte-lane merge networks in the 9K profile.
  assign full_word_write = write_strobe_i == 4'b1111;

  assign gpio_sampled = gpio_filtered_q;
  assign filtered_input_changed = |(gpio_sync_q ^ gpio_filter_sample_q);
  assign filter_settled = !filtered_input_changed &&
                          ((filter_cycles_q == 8'h00) ||
                           (filter_stable_count_q == filter_cycles_q));

  assign rise_events = gpio_sampled & ~gpio_in_previous_q;
  assign fall_events = ~gpio_sampled & gpio_in_previous_q;
  assign irq_events = (rise_events & rise_enable_q) |
                      (fall_events & fall_enable_q);
  // Snapshot trigger masks alias the normal GPIO edge-enable masks. This
  // keeps ordinary GPIO edge state and first-event diagnostics coherent while
  // avoiding a second 18-bit pair of configuration banks. Snapshot IRQ itself
  // remains independently selectable in SNAPSHOT_CTRL.
  assign snapshot_events = irq_events;
  assign snapshot_normal_event = snapshot_enable_q && (|snapshot_events);
  // A fault force always captures its own context; an earlier GPIO-only
  // snapshot must not hide a later safety event. Normal captures retain the
  // configured first-event/overwrite policy.
  assign snapshot_capture_event = snapshot_force_i ||
                                  (snapshot_normal_event &&
                                   (!snapshot_valid_q || snapshot_overwrite_q));
  assign snapshot_overflow_event =
    (snapshot_normal_event && snapshot_valid_q && !snapshot_overwrite_q) ||
    (snapshot_force_i && snapshot_valid_q);

  always_comb begin
    gpio_out_ext = '0;
    gpio_oe_ext = '0;
    gpio_in_ext = '0;
    rise_enable_ext = '0;
    fall_enable_ext = '0;
    irq_status_ext = '0;
    filter_scope_ext = '0;
    snapshot_event_ext = '0;
    snapshot_input_ext = '0;
    gpio_out_ext[GPIO_COUNT-1:0] = gpio_out_q;
    gpio_oe_ext[GPIO_COUNT-1:0] = gpio_oe_q;
    gpio_in_ext[GPIO_COUNT-1:0] = gpio_sampled;
    rise_enable_ext[GPIO_COUNT-1:0] = rise_enable_q;
    fall_enable_ext[GPIO_COUNT-1:0] = fall_enable_q;
    irq_status_ext[GPIO_COUNT-1:0] = irq_status_q;
    filter_scope_ext[GPIO_COUNT-1:0] = {GPIO_COUNT{1'b1}};
    snapshot_event_ext[GPIO_COUNT-1:0] = snapshot_event_q;
    snapshot_input_ext[GPIO_COUNT-1:0] = snapshot_input_q;
    snapshot_gpio_o = snapshot_input_ext;
  end

  always_comb begin
    snapshot_ctrl_read = '0;
    snapshot_ctrl_read[0] = snapshot_enable_q;
    snapshot_ctrl_read[1] = snapshot_irq_enable_q;
    snapshot_ctrl_read[2] = snapshot_overwrite_q;
    snapshot_status_read = '0;
    snapshot_status_read[0] = snapshot_valid_q;
    snapshot_status_read[1] = snapshot_overflow_q;
    snapshot_status_read[2] = snapshot_forced_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_OUT,
      REG_OUT_SET,
      REG_OUT_CLR,
      REG_OUT_XOR:           read_data_o = gpio_out_ext;
      REG_OE,
      REG_OE_SET,
      REG_OE_CLR:            read_data_o = gpio_oe_ext;
      REG_IN:                 read_data_o = gpio_in_ext;
      REG_RISE_EN:            read_data_o = rise_enable_ext;
      REG_FALL_EN:            read_data_o = fall_enable_ext;
      REG_IRQ_STATUS:         read_data_o = irq_status_ext;
      REG_FILTER_MASK:        read_data_o = filter_scope_ext;
      REG_FILTER_CYCLES:      read_data_o = {24'h000000, filter_cycles_q};
      REG_SNAPSHOT_CTRL:      read_data_o = snapshot_ctrl_read;
      REG_SNAPSHOT_RISE_EN:   read_data_o = rise_enable_ext;
      REG_SNAPSHOT_FALL_EN:   read_data_o = fall_enable_ext;
      REG_SNAPSHOT_STATUS:    read_data_o = snapshot_status_read;
      REG_SNAPSHOT_EVENT:     read_data_o = snapshot_event_ext;
      REG_SNAPSHOT_INPUT:     read_data_o = snapshot_input_ext;
      REG_SNAPSHOT_IRQ:       read_data_o = snapshot_irq_o;
      REG_SNAPSHOT_RESET:     read_data_o = snapshot_reset_o;
      REG_SNAPSHOT_TICKS:     read_data_o = snapshot_ticks_q;
      default:                 read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_out_q <= '0;
      gpio_oe_q <= '0;
      gpio_meta_q <= '0;
      gpio_sync_q <= '0;
      gpio_filtered_q <= '0;
      gpio_filter_sample_q <= '0;
      filter_stable_count_q <= 8'h00;
      gpio_in_previous_q <= '0;
      rise_enable_q <= '0;
      fall_enable_q <= '0;
      irq_status_q <= '0;
      filter_cycles_q <= 8'h00;
      snapshot_enable_q <= 1'b0;
      snapshot_irq_enable_q <= 1'b0;
      snapshot_overwrite_q <= 1'b0;
      snapshot_valid_q <= 1'b0;
      snapshot_overflow_q <= 1'b0;
      snapshot_forced_q <= 1'b0;
      snapshot_event_q <= '0;
      snapshot_input_q <= '0;
      snapshot_irq_q <= '0;
      snapshot_reset_q <= '0;
      snapshot_ticks_q <= '0;
    end else begin
      // No logic below this point uses a raw asynchronous GPIO level.
      gpio_meta_q <= gpio_in_i;
      gpio_sync_q <= gpio_meta_q;
      gpio_in_previous_q <= gpio_sampled;
      irq_status_q <= irq_status_q | irq_events;

      if (filter_cycles_q == 8'h00) begin
        gpio_filtered_q <= gpio_sync_q;
        gpio_filter_sample_q <= gpio_sync_q;
        filter_stable_count_q <= 8'h00;
      end else if (filtered_input_changed) begin
        gpio_filter_sample_q <= gpio_sync_q;
        filter_stable_count_q <= 8'h00;
      end else if (!filter_settled) begin
        filter_stable_count_q <= filter_stable_count_q + 8'd1;
      end else begin
        gpio_filtered_q <= gpio_sync_q;
      end

      if (snapshot_capture_event) begin
        snapshot_valid_q <= 1'b1;
        snapshot_forced_q <= snapshot_force_i;
        snapshot_event_q <= snapshot_events;
        snapshot_input_q <= gpio_sampled;
        // FAULT0's trip request and its IRQ latch become visible in the same
        // clock edge. Include that source explicitly in a forced capture so
        // the retained black-box record always identifies its own cause,
        // rather than observing the pre-trip IRQ vector from the prior edge.
        snapshot_irq_q <= irq_active_i[18:8] |
                          (snapshot_force_i ? 11'b100_0000_0000 : 11'b0);
        snapshot_reset_q <= reset_cause_i[2:0];
        snapshot_ticks_q <= run_ticks_i;
      end
      if (snapshot_overflow_event) begin
        snapshot_overflow_q <= 1'b1;
      end

      if (req_i && write_i && full_word_write) begin
        unique case (addr_i[7:2])
          REG_OUT: gpio_out_q <= write_data_i[GPIO_COUNT-1:0];
          REG_OUT_SET: gpio_out_q <= gpio_out_q | write_data_i[GPIO_COUNT-1:0];
          REG_OUT_CLR: gpio_out_q <= gpio_out_q & ~write_data_i[GPIO_COUNT-1:0];
          REG_OUT_XOR: gpio_out_q <= gpio_out_q ^ write_data_i[GPIO_COUNT-1:0];
          REG_OE: gpio_oe_q <= write_data_i[GPIO_COUNT-1:0];
          REG_OE_SET: gpio_oe_q <= gpio_oe_q | write_data_i[GPIO_COUNT-1:0];
          REG_OE_CLR: gpio_oe_q <= gpio_oe_q & ~write_data_i[GPIO_COUNT-1:0];
          REG_RISE_EN: rise_enable_q <= write_data_i[GPIO_COUNT-1:0];
          REG_FALL_EN: fall_enable_q <= write_data_i[GPIO_COUNT-1:0];
          REG_IRQ_STATUS: begin
            // Write-one-to-clear. An edge arriving in this cycle wins.
            irq_status_q <= (irq_status_q & ~write_data_i[GPIO_COUNT-1:0]) |
                            irq_events;
          end
          REG_FILTER_CYCLES: begin
            filter_cycles_q <= write_data_i[7:0];
            gpio_filter_sample_q <= gpio_sync_q;
            filter_stable_count_q <= 8'h00;
          end
          REG_SNAPSHOT_CTRL: begin
            snapshot_enable_q <= write_data_i[0];
            snapshot_irq_enable_q <= write_data_i[1];
            snapshot_overwrite_q <= write_data_i[2];
          end
          REG_SNAPSHOT_RISE_EN:
            rise_enable_q <= write_data_i[GPIO_COUNT-1:0];
          REG_SNAPSHOT_FALL_EN:
            fall_enable_q <= write_data_i[GPIO_COUNT-1:0];
          REG_SNAPSHOT_STATUS: begin
            // Captures in the same clock win over W1C, exactly like IRQ_STATUS.
            if (write_data_i[0]) begin
              snapshot_valid_q <= snapshot_capture_event;
              snapshot_forced_q <= snapshot_capture_event && snapshot_force_i;
            end
            if (write_data_i[1]) begin
              snapshot_overflow_q <= snapshot_overflow_event;
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
