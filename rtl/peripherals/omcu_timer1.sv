`default_nettype none

// Resource-bounded TIMER1 for the Tang Nano 9K profile. It combines a
// 16-bit prescaled compare timer, dual filtered input capture, and a
// quadrature decoder. The two inputs always pass through a two-flop
// synchronizer followed by a programmable 0..255-cycle stability filter;
// this is deliberately not an asynchronous high-speed counter.
//
// The MMIO page stays word addressed, but TIMER1 count/capture/position use
// their documented low 16 bits. Keeping this peripheral narrow is what lets
// the complete P0/P1 profile fit in the GW1NR-9C alongside Boot ROM/User Flash.
module omcu_timer1 (
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

  input  logic        capture_a_i,
  input  logic        capture_b_i,
  output logic        irq_o
);

  localparam logic [5:0] REG_CTRL      = 6'h00;
  localparam logic [5:0] REG_PRESCALE  = 6'h01;
  localparam logic [5:0] REG_COUNT     = 6'h02;
  localparam logic [5:0] REG_COMPARE   = 6'h03;
  localparam logic [5:0] REG_FILTER    = 6'h04;
  localparam logic [5:0] REG_CAPTURE_A = 6'h05;
  localparam logic [5:0] REG_CAPTURE_B = 6'h06;
  localparam logic [5:0] REG_ENCODER   = 6'h07;
  localparam logic [5:0] REG_STATUS    = 6'h08;

  logic        timer_enable_q;
  logic        irq_enable_q;
  logic        auto_reload_q;
  logic        capture_a_enable_q;
  logic        capture_b_enable_q;
  logic        capture_a_falling_q;
  logic        capture_b_falling_q;
  logic        encoder_enable_q;
  logic        encoder_reverse_q;
  logic [15:0] prescale_q;
  logic [15:0] prescale_count_q;
  logic [15:0] count_q;
  logic [15:0] compare_q;
  logic [7:0]  filter_q;
  logic [15:0] capture_a_q;
  logic [15:0] capture_b_q;
  logic [15:0] encoder_position_q;

  logic capture_a_meta_q;
  logic capture_a_sync_q;
  logic capture_a_filtered_q;
  logic [7:0] capture_a_filter_count_q;
  logic capture_b_meta_q;
  logic capture_b_sync_q;
  logic capture_b_filtered_q;
  logic [7:0] capture_b_filter_count_q;
  logic [1:0] encoder_state_q;
  logic       encoder_direction_q;

  logic compare_pending_q;
  logic capture_a_pending_q;
  logic capture_b_pending_q;
  logic encoder_step_pending_q;
  logic encoder_illegal_pending_q;

  logic counter_tick;
  logic compare_event;
  logic capture_a_filter_accept;
  logic capture_b_filter_accept;
  logic capture_a_filtered_next;
  logic capture_b_filtered_next;
  logic capture_a_rise_event;
  logic capture_a_fall_event;
  logic capture_b_rise_event;
  logic capture_b_fall_event;
  logic capture_a_event;
  logic capture_b_event;
  logic [1:0] encoder_input_next;
  logic encoder_step_event;
  logic encoder_illegal_event;
  logic encoder_forward_event;
  logic encoder_increment_event;

  logic [31:0] ctrl_read;
  logic [31:0] status_read;

  function automatic logic [15:0] merge_low16(
    input logic [15:0] old_value,
    input logic [31:0] new_value,
    input logic [3:0] strobe
  );
    logic [15:0] byte_mask;
    begin
      byte_mask = {{8{strobe[1]}}, {8{strobe[0]}}};
      merge_low16 = (old_value & ~byte_mask) | (new_value[15:0] & byte_mask);
    end
  endfunction

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = irq_enable_q && (compare_pending_q || capture_a_pending_q ||
                                  capture_b_pending_q || encoder_step_pending_q ||
                                  encoder_illegal_pending_q);
  assign counter_tick = timer_enable_q && (prescale_count_q == prescale_q);
  assign compare_event = counter_tick && (count_q == compare_q);
  assign capture_a_filter_accept = (capture_a_sync_q != capture_a_filtered_q) &&
                                   (capture_a_filter_count_q == filter_q);
  assign capture_b_filter_accept = (capture_b_sync_q != capture_b_filtered_q) &&
                                   (capture_b_filter_count_q == filter_q);
  assign capture_a_filtered_next = capture_a_filter_accept ? capture_a_sync_q :
                                                           capture_a_filtered_q;
  assign capture_b_filtered_next = capture_b_filter_accept ? capture_b_sync_q :
                                                           capture_b_filtered_q;
  assign capture_a_rise_event = capture_a_filter_accept && capture_a_sync_q;
  assign capture_a_fall_event = capture_a_filter_accept && !capture_a_sync_q;
  assign capture_b_rise_event = capture_b_filter_accept && capture_b_sync_q;
  assign capture_b_fall_event = capture_b_filter_accept && !capture_b_sync_q;
  assign capture_a_event = capture_a_enable_q &&
                           (capture_a_falling_q ? capture_a_fall_event :
                                                  capture_a_rise_event);
  assign capture_b_event = capture_b_enable_q &&
                           (capture_b_falling_q ? capture_b_fall_event :
                                                  capture_b_rise_event);
  assign encoder_input_next = {capture_a_filtered_next, capture_b_filtered_next};
  assign encoder_increment_event = encoder_step_event &&
                                   (encoder_forward_event ^ encoder_reverse_q);

  always_comb begin
    encoder_step_event = 1'b0;
    encoder_illegal_event = 1'b0;
    encoder_forward_event = 1'b0;
    if (encoder_enable_q && (encoder_input_next != encoder_state_q)) begin
      // Forward order: 00 -> 01 -> 11 -> 10 -> 00. A simultaneous two-bit
      // transition is an explicit diagnostic event, never two inferred steps.
      unique case ({encoder_state_q, encoder_input_next})
        4'b0001, 4'b0111, 4'b1110, 4'b1000: begin
          encoder_step_event = 1'b1;
          encoder_forward_event = 1'b1;
        end
        4'b0010, 4'b1011, 4'b1101, 4'b0100: begin
          encoder_step_event = 1'b1;
        end
        default: encoder_illegal_event = 1'b1;
      endcase
    end
  end

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = timer_enable_q;
    ctrl_read[1] = irq_enable_q;
    ctrl_read[2] = auto_reload_q;
    ctrl_read[3] = capture_a_enable_q;
    ctrl_read[4] = capture_b_enable_q;
    ctrl_read[5] = capture_a_falling_q;
    ctrl_read[6] = capture_b_falling_q;
    ctrl_read[7] = encoder_enable_q;
    ctrl_read[8] = encoder_reverse_q;

    status_read = '0;
    status_read[0] = compare_pending_q;
    status_read[1] = capture_a_pending_q;
    status_read[2] = capture_b_pending_q;
    status_read[3] = encoder_step_pending_q;
    status_read[4] = encoder_illegal_pending_q;
    status_read[5] = capture_a_filtered_q;
    status_read[6] = capture_b_filtered_q;
    status_read[7] = encoder_direction_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:      read_data_o = ctrl_read;
      REG_PRESCALE:  read_data_o = {16'h0000, prescale_q};
      REG_COUNT:     read_data_o = {16'h0000, count_q};
      REG_COMPARE:   read_data_o = {16'h0000, compare_q};
      REG_FILTER:    read_data_o = {24'h000000, filter_q};
      REG_CAPTURE_A: read_data_o = {16'h0000, capture_a_q};
      REG_CAPTURE_B: read_data_o = {16'h0000, capture_b_q};
      REG_ENCODER:   read_data_o = {{16{encoder_position_q[15]}}, encoder_position_q};
      REG_STATUS:    read_data_o = status_read;
      default:       read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      timer_enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      auto_reload_q <= 1'b0;
      capture_a_enable_q <= 1'b0;
      capture_b_enable_q <= 1'b0;
      capture_a_falling_q <= 1'b0;
      capture_b_falling_q <= 1'b0;
      encoder_enable_q <= 1'b0;
      encoder_reverse_q <= 1'b0;
      prescale_q <= 16'h0000;
      prescale_count_q <= 16'h0000;
      count_q <= 16'h0000;
      compare_q <= 16'hffff;
      filter_q <= 8'h00;
      capture_a_q <= 16'h0000;
      capture_b_q <= 16'h0000;
      encoder_position_q <= 16'h0000;
      capture_a_meta_q <= 1'b0;
      capture_a_sync_q <= 1'b0;
      capture_a_filtered_q <= 1'b0;
      capture_a_filter_count_q <= 8'h00;
      capture_b_meta_q <= 1'b0;
      capture_b_sync_q <= 1'b0;
      capture_b_filtered_q <= 1'b0;
      capture_b_filter_count_q <= 8'h00;
      encoder_state_q <= 2'b00;
      encoder_direction_q <= 1'b0;
      compare_pending_q <= 1'b0;
      capture_a_pending_q <= 1'b0;
      capture_b_pending_q <= 1'b0;
      encoder_step_pending_q <= 1'b0;
      encoder_illegal_pending_q <= 1'b0;
    end else begin
      // Never consume raw asynchronous pins below this point.
      capture_a_meta_q <= capture_a_i;
      capture_a_sync_q <= capture_a_meta_q;
      capture_b_meta_q <= capture_b_i;
      capture_b_sync_q <= capture_b_meta_q;

      if (capture_a_sync_q == capture_a_filtered_q) begin
        capture_a_filter_count_q <= 8'h00;
      end else if (capture_a_filter_accept) begin
        capture_a_filtered_q <= capture_a_sync_q;
        capture_a_filter_count_q <= 8'h00;
      end else begin
        capture_a_filter_count_q <= capture_a_filter_count_q + 8'd1;
      end
      if (capture_b_sync_q == capture_b_filtered_q) begin
        capture_b_filter_count_q <= 8'h00;
      end else if (capture_b_filter_accept) begin
        capture_b_filtered_q <= capture_b_sync_q;
        capture_b_filter_count_q <= 8'h00;
      end else begin
        capture_b_filter_count_q <= capture_b_filter_count_q + 8'd1;
      end
      encoder_state_q <= encoder_input_next;

      if (timer_enable_q) begin
        if (counter_tick) begin
          prescale_count_q <= 16'h0000;
          if (count_q == compare_q) begin
            if (auto_reload_q) begin
              count_q <= 16'h0000;
            end else begin
              timer_enable_q <= 1'b0;
            end
          end else begin
            count_q <= count_q + 16'd1;
          end
        end else begin
          prescale_count_q <= prescale_count_q + 16'd1;
        end
      end else begin
        prescale_count_q <= 16'h0000;
      end

      if (compare_event) compare_pending_q <= 1'b1;
      if (capture_a_event) begin
        capture_a_q <= count_q;
        capture_a_pending_q <= 1'b1;
      end
      if (capture_b_event) begin
        capture_b_q <= count_q;
        capture_b_pending_q <= 1'b1;
      end
      if (encoder_step_event) begin
        if (encoder_increment_event) begin
          encoder_position_q <= encoder_position_q + 16'd1;
          encoder_direction_q <= 1'b1;
        end else begin
          encoder_position_q <= encoder_position_q - 16'd1;
          encoder_direction_q <= 1'b0;
        end
        encoder_step_pending_q <= 1'b1;
      end
      if (encoder_illegal_event) encoder_illegal_pending_q <= 1'b1;

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: if (write_strobe_i[0]) begin
            timer_enable_q <= write_data_i[0];
            irq_enable_q <= write_data_i[1];
            auto_reload_q <= write_data_i[2];
            capture_a_enable_q <= write_data_i[3];
            capture_b_enable_q <= write_data_i[4];
            capture_a_falling_q <= write_data_i[5];
            capture_b_falling_q <= write_data_i[6];
            encoder_enable_q <= write_data_i[7];
            encoder_reverse_q <= write_data_i[8];
          end
          REG_PRESCALE: prescale_q <= merge_low16(
            prescale_q, write_data_i, write_strobe_i
          );
          REG_COUNT: count_q <= merge_low16(count_q, write_data_i, write_strobe_i);
          REG_COMPARE: compare_q <= merge_low16(compare_q, write_data_i, write_strobe_i);
          REG_FILTER: if (write_strobe_i[0]) begin
            filter_q <= write_data_i[7:0];
            capture_a_filter_count_q <= 8'h00;
            capture_b_filter_count_q <= 8'h00;
          end
          REG_ENCODER: encoder_position_q <= merge_low16(
            encoder_position_q, write_data_i, write_strobe_i
          );
          REG_STATUS: if (write_strobe_i[0]) begin
            if (write_data_i[0]) compare_pending_q <= compare_event;
            if (write_data_i[1]) capture_a_pending_q <= capture_a_event;
            if (write_data_i[2]) capture_b_pending_q <= capture_b_event;
            if (write_data_i[3]) encoder_step_pending_q <= encoder_step_event;
            if (write_data_i[4]) encoder_illegal_pending_q <= encoder_illegal_event;
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
