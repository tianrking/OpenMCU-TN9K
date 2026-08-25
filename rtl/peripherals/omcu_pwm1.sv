`default_nettype none

// Four edge-aligned PWM outputs driven from one shared 16-bit prescaler and
// counter. They consequently have common phase, while the low 16-bit PERIOD
// and DUTY registers give predictable resource use on GW1NR-9C. This block is
// intentionally not a complementary/dead-time/high-voltage gate driver.
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
  logic [15:0] period_q;
  logic [15:0] duty0_q;
  logic [15:0] duty1_q;
  logic [15:0] duty2_q;
  logic [15:0] duty3_q;
  logic [15:0] count_q;
  logic        tick;
  logic [3:0]  active_level;
  logic [31:0] ctrl_read;

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
  assign tick = enable_q && (prescale_count_q == prescale_q);
  assign active_level[0] = count_q < duty0_q;
  assign active_level[1] = count_q < duty1_q;
  assign active_level[2] = count_q < duty2_q;
  assign active_level[3] = count_q < duty3_q;
  // Disabled means a definite low output even when an invert bit was left set.
  assign pwm_o = enable_q ? (active_level ^ invert_q) : 4'b0000;

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
      REG_PERIOD:   read_data_o = {16'h0000, period_q};
      REG_DUTY0:    read_data_o = {16'h0000, duty0_q};
      REG_DUTY1:    read_data_o = {16'h0000, duty1_q};
      REG_DUTY2:    read_data_o = {16'h0000, duty2_q};
      REG_DUTY3:    read_data_o = {16'h0000, duty3_q};
      REG_COUNT:    read_data_o = {16'h0000, count_q};
      default:       read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      invert_q <= 4'b0000;
      prescale_q <= 16'h0000;
      prescale_count_q <= 16'h0000;
      period_q <= 16'hffff;
      duty0_q <= 16'h0000;
      duty1_q <= 16'h0000;
      duty2_q <= 16'h0000;
      duty3_q <= 16'h0000;
      count_q <= 16'h0000;
    end else begin
      if (enable_q) begin
        if (tick) begin
          prescale_count_q <= 16'h0000;
          if (count_q >= period_q) begin
            count_q <= 16'h0000;
          end else begin
            count_q <= count_q + 16'd1;
          end
        end else begin
          prescale_count_q <= prescale_count_q + 16'd1;
        end
      end else begin
        prescale_count_q <= 16'h0000;
        count_q <= 16'h0000;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: if (write_strobe_i[0]) begin
            enable_q <= write_data_i[0];
            invert_q <= write_data_i[7:4];
            if (!write_data_i[0]) begin
              prescale_count_q <= 16'h0000;
              count_q <= 16'h0000;
            end
          end
          REG_PRESCALE: prescale_q <= merge_low16(
            prescale_q, write_data_i, write_strobe_i
          );
          REG_PERIOD: period_q <= merge_low16(period_q, write_data_i, write_strobe_i);
          REG_DUTY0: duty0_q <= merge_low16(duty0_q, write_data_i, write_strobe_i);
          REG_DUTY1: duty1_q <= merge_low16(duty1_q, write_data_i, write_strobe_i);
          REG_DUTY2: duty2_q <= merge_low16(duty2_q, write_data_i, write_strobe_i);
          REG_DUTY3: duty3_q <= merge_low16(duty3_q, write_data_i, write_strobe_i);
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
