`default_nettype none

// Tang Nano 9K expansion-pad alternate-function selector.  GPIO remains the
// reset/default owner of every expansion pad; an application explicitly sets
// one bit before a dedicated peripheral can claim its documented pair/group.
// The module is intentionally tiny and has no hidden board pin numbers.
module omcu_pinmux (
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

  output logic        uart1_enable_o,
  output logic        pwm1_enable_o,
  output logic        timer1_enable_o,
  output logic        pulse0_enable_o
);

  localparam logic [5:0] REG_CTRL = 6'h00;

  logic uart1_enable_q;
  logic pwm1_enable_q;
  logic timer1_enable_q;
  logic pulse0_enable_q;
  logic [31:0] ctrl_read;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign uart1_enable_o = uart1_enable_q;
  assign pwm1_enable_o = pwm1_enable_q;
  assign timer1_enable_o = timer1_enable_q;
  assign pulse0_enable_o = pulse0_enable_q;

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = uart1_enable_q;
    ctrl_read[1] = pwm1_enable_q;
    ctrl_read[2] = timer1_enable_q;
    ctrl_read[3] = pulse0_enable_q;
    read_data_o = (addr_i[7:2] == REG_CTRL) ? ctrl_read : 32'h0000_0000;
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      uart1_enable_q <= 1'b0;
      pwm1_enable_q <= 1'b0;
      timer1_enable_q <= 1'b0;
      pulse0_enable_q <= 1'b0;
    end else if (req_i && write_i && addr_i[7:2] == REG_CTRL &&
                 write_strobe_i[0]) begin
      uart1_enable_q <= write_data_i[0];
      pwm1_enable_q <= write_data_i[1];
      timer1_enable_q <= write_data_i[2];
      pulse0_enable_q <= write_data_i[3];
    end
  end

endmodule

`default_nettype wire
