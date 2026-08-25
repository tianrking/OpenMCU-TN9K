`default_nettype none

// A clock-domain-local watchdog with an ABI-compatible basic mode plus an
// optional supervised mode: pretimeout warning, minimum feed window and up to
// eight software heartbeats. The platform wrapper still owns reset length and
// retained reset cause; this peripheral emits only a single reset-request pulse.
module omcu_wdt #(
  parameter logic [31:0] FEED_MAGIC = 32'h51f1_5eed
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

  output logic        irq_o,
  output logic        reset_req_o
);

  localparam logic [5:0] REG_CTRL               = 6'h00;
  localparam logic [5:0] REG_TIMEOUT            = 6'h01;
  localparam logic [5:0] REG_FEED               = 6'h02;
  localparam logic [5:0] REG_STATUS             = 6'h03;
  localparam logic [5:0] REG_PRETIMEOUT         = 6'h04;
  localparam logic [5:0] REG_WINDOW_MIN         = 6'h05;
  localparam logic [5:0] REG_HEARTBEAT_REQUIRED = 6'h06;
  localparam logic [5:0] REG_HEARTBEAT_SEEN     = 6'h07;
  localparam logic [5:0] REG_HEARTBEAT_KICK     = 6'h08;
  localparam logic [5:0] REG_COUNT              = 6'h09;

  logic        enable_q;
  logic        reset_enable_q;
  logic        irq_enable_q;
  logic        pretimeout_irq_enable_q;
  logic        window_enable_q;
  logic        heartbeat_enable_q;
  logic [31:0] timeout_q;
  logic [31:0] pretimeout_q;
  logic [31:0] window_min_q;
  logic [31:0] count_q;
  logic [7:0]  heartbeat_required_q;
  logic [7:0]  heartbeat_seen_q;
  logic        expired_q;
  logic        pretimeout_pending_q;
  logic        window_violation_q;
  logic        heartbeat_missing_q;
  logic        feed_rejected_q;
  logic        reset_req_q;
  logic        window_open_q;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;
  logic        full_word_write;
  logic        feed_command;
  logic [7:0]  heartbeat_kick_bits;
  logic        heartbeat_complete;
  logic        pretimeout_event;
  logic        expiry_event;
  logic        window_open_event;
  logic        feed_window_violation;
  logic        feed_heartbeat_missing;
  logic        feed_failure;
  logic        feed_expired;
  logic        feed_accepted;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = (expired_q && irq_enable_q) ||
                 (pretimeout_pending_q && pretimeout_irq_enable_q);
  assign reset_req_o = reset_req_q;
  // Safety-relevant watchdog operations are one atomic 32-bit store.  Besides
  // preventing torn timeout/window configuration, this deliberately replaces
  // wide byte-lane merge networks with registered epoch state.  Software must
  // stop the WDT before changing its configuration; it may always feed and
  // kick heartbeats while enabled.
  assign full_word_write = write_strobe_i == 4'b1111;
  assign feed_command = req_i && write_i && (addr_i[7:2] == REG_FEED) &&
                        full_word_write && (write_data_i == FEED_MAGIC);
  assign heartbeat_kick_bits = (req_i && write_i &&
                                (addr_i[7:2] == REG_HEARTBEAT_KICK) &&
                                full_word_write) ? write_data_i[7:0] : 8'h00;
  assign heartbeat_complete =
    (heartbeat_seen_q & heartbeat_required_q) == heartbeat_required_q;
  // PRETIMEOUT=0 deliberately disables the warning stage, preserving the
  // simple legacy watchdog contract without a second control bit.
  assign pretimeout_event = enable_q && (pretimeout_q != 32'h0000_0000) &&
                            (count_q == pretimeout_q);
  // Configuration is accepted only while disabled, and every started epoch
  // begins at zero.  Equality is consequently sufficient for expiry and is
  // notably cheaper than a 32-bit greater-or-equal comparator in the 9K part.
  assign expiry_event = enable_q && (count_q == timeout_q);
  // WINDOW_MIN needs no wide less-than comparator.  This flag is asserted on
  // the threshold tick; the equality term admits a feed on that exact tick,
  // matching the documented count >= WINDOW_MIN contract.
  assign window_open_event = enable_q && window_enable_q &&
                             (count_q == window_min_q);
  assign feed_window_violation = feed_command && window_enable_q &&
                                 !window_open_q && !window_open_event;
  assign feed_heartbeat_missing = feed_command && heartbeat_enable_q &&
                                  !heartbeat_complete;
  assign feed_failure = feed_window_violation || feed_heartbeat_missing;
  assign feed_expired = feed_command && expiry_event;
  assign feed_accepted = feed_command && !feed_failure && !expiry_event;

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = reset_enable_q;
    ctrl_read[2] = irq_enable_q;
    ctrl_read[3] = pretimeout_irq_enable_q;
    ctrl_read[4] = window_enable_q;
    ctrl_read[5] = heartbeat_enable_q;
    status_read = '0;
    status_read[0] = expired_q;
    status_read[1] = reset_req_q;
    status_read[2] = pretimeout_pending_q;
    status_read[3] = window_violation_q;
    status_read[4] = heartbeat_missing_q;
    status_read[5] = feed_rejected_q;

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:               read_data_o = ctrl_read;
      REG_TIMEOUT:            read_data_o = timeout_q;
      REG_STATUS:             read_data_o = status_read;
      REG_PRETIMEOUT:         read_data_o = pretimeout_q;
      REG_WINDOW_MIN:         read_data_o = window_min_q;
      REG_HEARTBEAT_REQUIRED: read_data_o = {24'h000000, heartbeat_required_q};
      REG_HEARTBEAT_SEEN:     read_data_o = {24'h000000, heartbeat_seen_q};
      REG_COUNT:              read_data_o = count_q;
      default:                read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      reset_enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      pretimeout_irq_enable_q <= 1'b0;
      window_enable_q <= 1'b0;
      heartbeat_enable_q <= 1'b0;
      timeout_q <= 32'hffff_ffff;
      pretimeout_q <= 32'h0000_0000;
      window_min_q <= 32'h0000_0000;
      count_q <= 32'h0000_0000;
      heartbeat_required_q <= 8'h00;
      heartbeat_seen_q <= 8'h00;
      expired_q <= 1'b0;
      pretimeout_pending_q <= 1'b0;
      window_violation_q <= 1'b0;
      heartbeat_missing_q <= 1'b0;
      feed_rejected_q <= 1'b0;
      reset_req_q <= 1'b0;
      window_open_q <= 1'b0;
    end else begin
      // Reset requests are pulses. A platform sequencer records the cause and
      // holds the complete SoC in reset for its own defined interval.
      reset_req_q <= 1'b0;

      if (enable_q) begin
        if (expiry_event) begin
          count_q <= 32'h0000_0000;
          expired_q <= 1'b1;
          reset_req_q <= reset_enable_q;
          window_open_q <= 1'b0;
        end else begin
          count_q <= count_q + 32'd1;
        end
      end
      if (window_open_event) begin
        window_open_q <= 1'b1;
      end
      if (pretimeout_event) begin
        pretimeout_pending_q <= 1'b1;
      end
      if (heartbeat_kick_bits != 8'h00) begin
        heartbeat_seen_q <= heartbeat_seen_q | heartbeat_kick_bits;
      end
      if (feed_accepted) begin
        count_q <= 32'h0000_0000;
        heartbeat_seen_q <= 8'h00;
        window_open_q <= 1'b0;
      end
      if (feed_failure) begin
        count_q <= 32'h0000_0000;
        expired_q <= 1'b1;
        window_violation_q <= window_violation_q || feed_window_violation;
        heartbeat_missing_q <= heartbeat_missing_q || feed_heartbeat_missing;
        feed_rejected_q <= 1'b1;
        heartbeat_seen_q <= 8'h00;
        reset_req_q <= reset_enable_q;
        window_open_q <= 1'b0;
      end else if (feed_expired) begin
        // A feed exactly on the expiry clock never rescues the watchdog.
        feed_rejected_q <= 1'b1;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: begin
            if (full_word_write && (!enable_q || !write_data_i[0])) begin
              enable_q <= write_data_i[0];
              reset_enable_q <= write_data_i[1];
              irq_enable_q <= write_data_i[2];
              pretimeout_irq_enable_q <= write_data_i[3];
              window_enable_q <= write_data_i[4];
              heartbeat_enable_q <= write_data_i[5];
              // Beginning a new enabled epoch or disabling the WDT discards
              // stale progress/heartbeats. Reconfiguration while already on
              // leaves the active epoch intact.
              if (!write_data_i[0] || !enable_q) begin
                count_q <= 32'h0000_0000;
                heartbeat_seen_q <= 8'h00;
                window_open_q <= 1'b0;
              end
            end
          end
          REG_TIMEOUT: if (full_word_write && !enable_q)
            timeout_q <= write_data_i;
          REG_PRETIMEOUT: if (full_word_write && !enable_q)
            pretimeout_q <= write_data_i;
          REG_WINDOW_MIN: if (full_word_write && !enable_q)
            window_min_q <= write_data_i;
          REG_HEARTBEAT_REQUIRED: if (full_word_write && !enable_q)
            heartbeat_required_q <= write_data_i[7:0];
          REG_STATUS: begin
            // W1C; events in the exact clock always win over an acknowledgement.
            if (full_word_write && write_data_i[0]) begin
              expired_q <= expiry_event || feed_failure;
            end
            if (full_word_write && write_data_i[2]) begin
              pretimeout_pending_q <= pretimeout_event;
            end
            if (full_word_write && write_data_i[3]) begin
              window_violation_q <= feed_window_violation;
            end
            if (full_word_write && write_data_i[4]) begin
              heartbeat_missing_q <= feed_heartbeat_missing;
            end
            if (full_word_write && write_data_i[5]) begin
              feed_rejected_q <= feed_failure || feed_expired;
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
