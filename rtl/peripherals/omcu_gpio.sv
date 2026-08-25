`default_nettype none

// Portable GPIO block for the OpenMCU single-master MMIO contract.
//
// Every input first crosses a two-flop synchronizer. A selected input can
// additionally pass through a programmable stability filter before it reaches
// GPIO.IN, edge detection, GPIO IRQ status, or the event snapshot. The filter
// value N means N+1 consecutive mismatched synchronized samples are required
// to accept a new level; N=0 is therefore the lowest-latency filtered setting.
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
  logic [GPIO_COUNT*8-1:0] filter_count_q;
  logic [GPIO_COUNT-1:0] gpio_in_previous_q;
  logic [GPIO_COUNT-1:0] rise_enable_q;
  logic [GPIO_COUNT-1:0] fall_enable_q;
  logic [GPIO_COUNT-1:0] irq_status_q;
  logic [GPIO_COUNT-1:0] filter_mask_q;
  logic [7:0] filter_cycles_q;

  logic snapshot_enable_q;
  logic snapshot_irq_enable_q;
  logic snapshot_overwrite_q;
  logic [GPIO_COUNT-1:0] snapshot_rise_enable_q;
  logic [GPIO_COUNT-1:0] snapshot_fall_enable_q;
  logic snapshot_valid_q;
  logic snapshot_overflow_q;
  logic [GPIO_COUNT-1:0] snapshot_event_q;
  logic [GPIO_COUNT-1:0] snapshot_input_q;
  logic [31:0] snapshot_irq_q;
  logic [31:0] snapshot_reset_q;
  logic [31:0] snapshot_ticks_q;

  logic [GPIO_COUNT-1:0] gpio_filtered_next;
  logic [GPIO_COUNT-1:0] gpio_sampled;
  logic [GPIO_COUNT-1:0] rise_events;
  logic [GPIO_COUNT-1:0] fall_events;
  logic [GPIO_COUNT-1:0] irq_events;
  logic [GPIO_COUNT-1:0] snapshot_events;
  logic snapshot_capture_event;
  logic snapshot_overflow_event;

  logic [31:0] gpio_out_ext;
  logic [31:0] gpio_oe_ext;
  logic [31:0] gpio_in_ext;
  logic [31:0] rise_enable_ext;
  logic [31:0] fall_enable_ext;
  logic [31:0] irq_status_ext;
  logic [31:0] filter_mask_ext;
  logic [31:0] snapshot_rise_enable_ext;
  logic [31:0] snapshot_fall_enable_ext;
  logic [31:0] snapshot_event_ext;
  logic [31:0] snapshot_input_ext;
  logic [31:0] write_masked_data;
  logic [31:0] gpio_out_merged;
  logic [31:0] gpio_oe_merged;
  logic [31:0] rise_enable_merged;
  logic [31:0] fall_enable_merged;
  logic [31:0] filter_mask_merged;
  logic [31:0] snapshot_rise_enable_merged;
  logic [31:0] snapshot_fall_enable_merged;
  logic [31:0] snapshot_ctrl_read;
  logic [31:0] snapshot_status_read;
  integer gpio_index;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign gpio_out_o = gpio_out_q;
  assign gpio_oe_o = gpio_oe_q;
  // Snapshot completion intentionally shares the established GPIO0 CPU IRQ.
  // Existing GPIO-only firmware is unaffected unless SNAPSHOT.IRQ_ENABLE is
  // explicitly set.
  assign irq_o = (|irq_status_q) ||
                 (snapshot_valid_q && snapshot_irq_enable_q);
  assign write_masked_data = write_data_i & `OMCU_WRITE_STROBE_MASK(write_strobe_i);
  assign gpio_out_merged = `OMCU_MERGE_WRITE(gpio_out_ext, write_data_i, write_strobe_i);
  assign gpio_oe_merged = `OMCU_MERGE_WRITE(gpio_oe_ext, write_data_i, write_strobe_i);
  assign rise_enable_merged = `OMCU_MERGE_WRITE(rise_enable_ext, write_data_i, write_strobe_i);
  assign fall_enable_merged = `OMCU_MERGE_WRITE(fall_enable_ext, write_data_i, write_strobe_i);
  assign filter_mask_merged = `OMCU_MERGE_WRITE(filter_mask_ext, write_data_i, write_strobe_i);
  assign snapshot_rise_enable_merged = `OMCU_MERGE_WRITE(
    snapshot_rise_enable_ext, write_data_i, write_strobe_i
  );
  assign snapshot_fall_enable_merged = `OMCU_MERGE_WRITE(
    snapshot_fall_enable_ext, write_data_i, write_strobe_i
  );

  always_comb begin
    gpio_filtered_next = gpio_filtered_q;
    gpio_sampled = '0;
    for (gpio_index = 0; gpio_index < GPIO_COUNT; gpio_index = gpio_index + 1) begin
      if ((gpio_sync_q[gpio_index] != gpio_filtered_q[gpio_index]) &&
          (filter_count_q[gpio_index * 8 +: 8] == filter_cycles_q)) begin
        gpio_filtered_next[gpio_index] = gpio_sync_q[gpio_index];
      end
      gpio_sampled[gpio_index] = filter_mask_q[gpio_index] ?
                                  gpio_filtered_q[gpio_index] : gpio_sync_q[gpio_index];
    end
  end

  assign rise_events = gpio_sampled & ~gpio_in_previous_q;
  assign fall_events = ~gpio_sampled & gpio_in_previous_q;
  assign irq_events = (rise_events & rise_enable_q) |
                      (fall_events & fall_enable_q);
  assign snapshot_events = (rise_events & snapshot_rise_enable_q) |
                           (fall_events & snapshot_fall_enable_q);
  assign snapshot_capture_event = snapshot_enable_q && (|snapshot_events) &&
                                  (!snapshot_valid_q || snapshot_overwrite_q);
  assign snapshot_overflow_event = snapshot_enable_q && (|snapshot_events) &&
                                   snapshot_valid_q && !snapshot_overwrite_q;

  always_comb begin
    gpio_out_ext = '0;
    gpio_oe_ext = '0;
    gpio_in_ext = '0;
    rise_enable_ext = '0;
    fall_enable_ext = '0;
    irq_status_ext = '0;
    filter_mask_ext = '0;
    snapshot_rise_enable_ext = '0;
    snapshot_fall_enable_ext = '0;
    snapshot_event_ext = '0;
    snapshot_input_ext = '0;
    gpio_out_ext[GPIO_COUNT-1:0] = gpio_out_q;
    gpio_oe_ext[GPIO_COUNT-1:0] = gpio_oe_q;
    gpio_in_ext[GPIO_COUNT-1:0] = gpio_sampled;
    rise_enable_ext[GPIO_COUNT-1:0] = rise_enable_q;
    fall_enable_ext[GPIO_COUNT-1:0] = fall_enable_q;
    irq_status_ext[GPIO_COUNT-1:0] = irq_status_q;
    filter_mask_ext[GPIO_COUNT-1:0] = filter_mask_q;
    snapshot_rise_enable_ext[GPIO_COUNT-1:0] = snapshot_rise_enable_q;
    snapshot_fall_enable_ext[GPIO_COUNT-1:0] = snapshot_fall_enable_q;
    snapshot_event_ext[GPIO_COUNT-1:0] = snapshot_event_q;
    snapshot_input_ext[GPIO_COUNT-1:0] = snapshot_input_q;
  end

  always_comb begin
    snapshot_ctrl_read = '0;
    snapshot_ctrl_read[0] = snapshot_enable_q;
    snapshot_ctrl_read[1] = snapshot_irq_enable_q;
    snapshot_ctrl_read[2] = snapshot_overwrite_q;
    snapshot_status_read = '0;
    snapshot_status_read[0] = snapshot_valid_q;
    snapshot_status_read[1] = snapshot_overflow_q;
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
      REG_FILTER_MASK:        read_data_o = filter_mask_ext;
      REG_FILTER_CYCLES:      read_data_o = {24'h000000, filter_cycles_q};
      REG_SNAPSHOT_CTRL:      read_data_o = snapshot_ctrl_read;
      REG_SNAPSHOT_RISE_EN:   read_data_o = snapshot_rise_enable_ext;
      REG_SNAPSHOT_FALL_EN:   read_data_o = snapshot_fall_enable_ext;
      REG_SNAPSHOT_STATUS:    read_data_o = snapshot_status_read;
      REG_SNAPSHOT_EVENT:     read_data_o = snapshot_event_ext;
      REG_SNAPSHOT_INPUT:     read_data_o = snapshot_input_ext;
      REG_SNAPSHOT_IRQ:       read_data_o = snapshot_irq_q;
      REG_SNAPSHOT_RESET:     read_data_o = snapshot_reset_q;
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
      filter_count_q <= '0;
      gpio_in_previous_q <= '0;
      rise_enable_q <= '0;
      fall_enable_q <= '0;
      irq_status_q <= '0;
      filter_mask_q <= '0;
      filter_cycles_q <= 8'h00;
      snapshot_enable_q <= 1'b0;
      snapshot_irq_enable_q <= 1'b0;
      snapshot_overwrite_q <= 1'b0;
      snapshot_rise_enable_q <= '0;
      snapshot_fall_enable_q <= '0;
      snapshot_valid_q <= 1'b0;
      snapshot_overflow_q <= 1'b0;
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

      for (gpio_index = 0; gpio_index < GPIO_COUNT; gpio_index = gpio_index + 1) begin
        if (gpio_sync_q[gpio_index] == gpio_filtered_q[gpio_index]) begin
          filter_count_q[gpio_index * 8 +: 8] <= 8'h00;
        end else if (gpio_filtered_next[gpio_index] != gpio_filtered_q[gpio_index]) begin
          gpio_filtered_q[gpio_index] <= gpio_filtered_next[gpio_index];
          filter_count_q[gpio_index * 8 +: 8] <= 8'h00;
        end else begin
          filter_count_q[gpio_index * 8 +: 8] <=
            filter_count_q[gpio_index * 8 +: 8] + 8'd1;
        end
      end

      if (snapshot_capture_event) begin
        snapshot_valid_q <= 1'b1;
        snapshot_event_q <= snapshot_events;
        snapshot_input_q <= gpio_sampled;
        snapshot_irq_q <= irq_active_i;
        snapshot_reset_q <= reset_cause_i;
        snapshot_ticks_q <= run_ticks_i;
      end
      if (snapshot_overflow_event) begin
        snapshot_overflow_q <= 1'b1;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_OUT: gpio_out_q <= gpio_out_merged[GPIO_COUNT-1:0];
          REG_OUT_SET: gpio_out_q <= gpio_out_q | write_masked_data[GPIO_COUNT-1:0];
          REG_OUT_CLR: gpio_out_q <= gpio_out_q & ~write_masked_data[GPIO_COUNT-1:0];
          REG_OUT_XOR: gpio_out_q <= gpio_out_q ^ write_masked_data[GPIO_COUNT-1:0];
          REG_OE: gpio_oe_q <= gpio_oe_merged[GPIO_COUNT-1:0];
          REG_OE_SET: gpio_oe_q <= gpio_oe_q | write_masked_data[GPIO_COUNT-1:0];
          REG_OE_CLR: gpio_oe_q <= gpio_oe_q & ~write_masked_data[GPIO_COUNT-1:0];
          REG_RISE_EN: rise_enable_q <= rise_enable_merged[GPIO_COUNT-1:0];
          REG_FALL_EN: fall_enable_q <= fall_enable_merged[GPIO_COUNT-1:0];
          REG_IRQ_STATUS: begin
            // Write-one-to-clear. An edge arriving in this cycle wins.
            irq_status_q <= (irq_status_q & ~write_masked_data[GPIO_COUNT-1:0]) |
                            irq_events;
          end
          REG_FILTER_MASK: filter_mask_q <= filter_mask_merged[GPIO_COUNT-1:0];
          REG_FILTER_CYCLES: if (write_strobe_i[0]) begin
            filter_cycles_q <= write_data_i[7:0];
            filter_count_q <= '0;
          end
          REG_SNAPSHOT_CTRL: if (write_strobe_i[0]) begin
            snapshot_enable_q <= write_data_i[0];
            snapshot_irq_enable_q <= write_data_i[1];
            snapshot_overwrite_q <= write_data_i[2];
          end
          REG_SNAPSHOT_RISE_EN:
            snapshot_rise_enable_q <= snapshot_rise_enable_merged[GPIO_COUNT-1:0];
          REG_SNAPSHOT_FALL_EN:
            snapshot_fall_enable_q <= snapshot_fall_enable_merged[GPIO_COUNT-1:0];
          REG_SNAPSHOT_STATUS: begin
            // Captures in the same clock win over W1C, exactly like IRQ_STATUS.
            if (write_strobe_i[0] && write_data_i[0]) begin
              snapshot_valid_q <= snapshot_capture_event;
            end
            if (write_strobe_i[0] && write_data_i[1]) begin
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
