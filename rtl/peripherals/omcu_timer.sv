`default_nettype none

// One compare-capable timer. It is intentionally simple and has no
// hidden clock-domain crossing; additional timers are separate instances.
module omcu_timer (
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

  import omcu_mmio_pkg::*;

  localparam logic [5:0] REG_CTRL      = 6'h00;
  localparam logic [5:0] REG_PRESCALE  = 6'h01;
  localparam logic [5:0] REG_COUNT     = 6'h02;
  localparam logic [5:0] REG_COMPARE   = 6'h03;
  localparam logic [5:0] REG_STATUS    = 6'h04;

  logic        enable_q;
  logic        irq_enable_q;
  logic        auto_reload_q;
  logic [15:0] prescale_q;
  logic [15:0] prescale_count_q;
  logic [31:0] count_q;
  logic [31:0] compare_q;
  logic        irq_pending_q;
  logic        counter_tick;
  logic        compare_event;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;
  logic [31:0] prescale_merged;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = irq_pending_q & irq_enable_q;
  assign counter_tick = enable_q && (prescale_count_q == prescale_q);
  assign compare_event = counter_tick && (count_q == compare_q);
  assign prescale_merged = merge_write({16'h0000, prescale_q}, write_data_i, write_strobe_i);

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = irq_enable_q;
    ctrl_read[2] = auto_reload_q;
    status_read = '0;
    status_read[0] = irq_pending_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:     read_data_o = ctrl_read;
      REG_PRESCALE: read_data_o = {16'h0000, prescale_q};
      REG_COUNT:    read_data_o = count_q;
      REG_COMPARE:  read_data_o = compare_q;
      REG_STATUS:   read_data_o = status_read;
      default:      read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      auto_reload_q <= 1'b0;
      prescale_q <= 16'h0000;
      prescale_count_q <= 16'h0000;
      count_q <= 32'h0000_0000;
      compare_q <= 32'hffff_ffff;
      irq_pending_q <= 1'b0;
    end else begin
      if (enable_q) begin
        if (counter_tick) begin
          prescale_count_q <= 16'h0000;
          if (count_q == compare_q) begin
            if (auto_reload_q) begin
              count_q <= 32'h0000_0000;
            end else begin
              // A non-reloading timer is one-shot and stops at the compare.
              enable_q <= 1'b0;
            end
          end else begin
            count_q <= count_q + 32'd1;
          end
        end else begin
          prescale_count_q <= prescale_count_q + 16'd1;
        end
      end else begin
        prescale_count_q <= 16'h0000;
      end

      if (compare_event) begin
        irq_pending_q <= 1'b1;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: begin
            if (write_strobe_i[0]) begin
              enable_q <= write_data_i[0];
              irq_enable_q <= write_data_i[1];
              auto_reload_q <= write_data_i[2];
            end
          end
          REG_PRESCALE: begin
            prescale_q <= prescale_merged[15:0];
          end
          REG_COUNT: begin
            count_q <= merge_write(count_q, write_data_i, write_strobe_i);
          end
          REG_COMPARE: begin
            compare_q <= merge_write(compare_q, write_data_i, write_strobe_i);
          end
          REG_STATUS: begin
            if (write_strobe_i[0] && write_data_i[0]) begin
              // W1C; a comparison in this exact clock cycle wins.
              irq_pending_q <= compare_event;
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
