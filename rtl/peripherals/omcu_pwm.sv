`default_nettype none

// One deterministic edge-aligned PWM channel.  The portable block exposes its
// raw logic output; a board wrapper decides whether it reaches a header, LED,
// motor-driver level shifter, or ASIC pad.
module omcu_pwm (
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

  output logic        pwm_o
);

  import omcu_mmio_pkg::*;

  localparam logic [5:0] REG_CTRL     = 6'h00;
  localparam logic [5:0] REG_PRESCALE = 6'h01;
  localparam logic [5:0] REG_PERIOD   = 6'h02;
  localparam logic [5:0] REG_DUTY     = 6'h03;
  localparam logic [5:0] REG_COUNT    = 6'h04;

  logic        enable_q;
  logic        invert_q;
  logic [15:0] prescale_q;
  logic [15:0] prescale_count_q;
  logic [31:0] period_q;
  logic [31:0] duty_q;
  logic [31:0] count_q;
  logic        tick;
  logic        active_level;
  logic [31:0] ctrl_read;
  logic [31:0] prescale_merged;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign tick = enable_q && (prescale_count_q == prescale_q);
  assign active_level = enable_q && (count_q < duty_q);
  assign pwm_o = active_level ^ invert_q;
  assign prescale_merged = merge_write({16'h0000, prescale_q}, write_data_i, write_strobe_i);

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = invert_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:     read_data_o = ctrl_read;
      REG_PRESCALE: read_data_o = {16'h0000, prescale_q};
      REG_PERIOD:   read_data_o = period_q;
      REG_DUTY:     read_data_o = duty_q;
      REG_COUNT:    read_data_o = count_q;
      default:      read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      invert_q <= 1'b0;
      prescale_q <= 16'h0000;
      prescale_count_q <= 16'h0000;
      period_q <= 32'h0000_ffff;
      duty_q <= 32'h0000_0000;
      count_q <= 32'h0000_0000;
    end else begin
      if (enable_q) begin
        if (tick) begin
          prescale_count_q <= 16'h0000;
          if (count_q >= period_q) begin
            count_q <= 32'h0000_0000;
          end else begin
            count_q <= count_q + 32'd1;
          end
        end else begin
          prescale_count_q <= prescale_count_q + 16'd1;
        end
      end else begin
        prescale_count_q <= 16'h0000;
        count_q <= 32'h0000_0000;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: begin
            if (write_strobe_i[0]) begin
              enable_q <= write_data_i[0];
              invert_q <= write_data_i[1];
              if (!write_data_i[0]) begin
                count_q <= 32'h0000_0000;
              end
            end
          end
          REG_PRESCALE: begin
            prescale_q <= prescale_merged[15:0];
          end
          REG_PERIOD: begin
            period_q <= merge_write(period_q, write_data_i, write_strobe_i);
          end
          REG_DUTY: begin
            duty_q <= merge_write(duty_q, write_data_i, write_strobe_i);
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
