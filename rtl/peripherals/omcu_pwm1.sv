`default_nettype none

// Four edge-aligned PWM outputs driven from one shared prescaler and counter.
// This keeps the resource cost small and guarantees a common phase for motors,
// LEDs or servo-style outputs that share a timing base.  It deliberately does
// not implement complementary pairs, dead time, break inputs or gate-driver
// safety logic; those belong in a separately reviewed power-stage design.
module omcu_pwm1 (
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

  output logic [3:0]  pwm_o
);

  localparam logic [5:0] REG_CTRL     = 6'h00;
  localparam logic [5:0] REG_PRESCALE = 6'h01;
  localparam logic [5:0] REG_PERIOD   = 6'h02;
  localparam logic [5:0] REG_DUTY0    = 6'h03;
  localparam logic [5:0] REG_DUTY1    = 6'h04;
  localparam logic [5:0] REG_DUTY2    = 6'h05;
  localparam logic [5:0] REG_DUTY3    = 6'h06;
  localparam logic [5:0] REG_COUNT    = 6'h07;

  logic        enable_q;
  logic [3:0]  invert_q;
  logic [15:0] prescale_q;
  logic [15:0] prescale_count_q;
  logic [31:0] period_q;
  logic [31:0] duty0_q;
  logic [31:0] duty1_q;
  logic [31:0] duty2_q;
  logic [31:0] duty3_q;
  logic [31:0] count_q;
  logic        tick;
  logic [3:0]  active_level;
  logic [31:0] ctrl_read;
  logic [31:0] ctrl_merged;
  logic [31:0] prescale_merged;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign tick = enable_q && (prescale_count_q == prescale_q);
  assign active_level[0] = count_q < duty0_q;
  assign active_level[1] = count_q < duty1_q;
  assign active_level[2] = count_q < duty2_q;
  assign active_level[3] = count_q < duty3_q;
  // Disabled is unconditionally low, including when a channel's invert bit
  // was left set.  This is the board wrapper's safe default before pinmux.
  assign pwm_o = enable_q ? (active_level ^ invert_q) : 4'b0000;
  assign ctrl_merged = `OMCU_MERGE_WRITE(ctrl_read, write_data_i, write_strobe_i);
  assign prescale_merged = `OMCU_MERGE_WRITE(
    {16'h0000, prescale_q}, write_data_i, write_strobe_i
  );

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[7:4] = invert_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:     read_data_o = ctrl_read;
      REG_PRESCALE: read_data_o = {16'h0000, prescale_q};
      REG_PERIOD:   read_data_o = period_q;
      REG_DUTY0:    read_data_o = duty0_q;
      REG_DUTY1:    read_data_o = duty1_q;
      REG_DUTY2:    read_data_o = duty2_q;
      REG_DUTY3:    read_data_o = duty3_q;
      REG_COUNT:    read_data_o = count_q;
      default:      read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      invert_q <= 4'b0000;
      prescale_q <= 16'h0000;
      prescale_count_q <= 16'h0000;
      period_q <= 32'h0000_ffff;
      duty0_q <= 32'h0000_0000;
      duty1_q <= 32'h0000_0000;
      duty2_q <= 32'h0000_0000;
      duty3_q <= 32'h0000_0000;
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
            enable_q <= ctrl_merged[0];
            invert_q <= ctrl_merged[7:4];
            if (!ctrl_merged[0]) begin
              prescale_count_q <= 16'h0000;
              count_q <= 32'h0000_0000;
            end
          end
          REG_PRESCALE: begin
            prescale_q <= prescale_merged[15:0];
          end
          REG_PERIOD: begin
            period_q <= `OMCU_MERGE_WRITE(period_q, write_data_i, write_strobe_i);
          end
          REG_DUTY0: begin
            duty0_q <= `OMCU_MERGE_WRITE(duty0_q, write_data_i, write_strobe_i);
          end
          REG_DUTY1: begin
            duty1_q <= `OMCU_MERGE_WRITE(duty1_q, write_data_i, write_strobe_i);
          end
          REG_DUTY2: begin
            duty2_q <= `OMCU_MERGE_WRITE(duty2_q, write_data_i, write_strobe_i);
          end
          REG_DUTY3: begin
            duty3_q <= `OMCU_MERGE_WRITE(duty3_q, write_data_i, write_strobe_i);
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
