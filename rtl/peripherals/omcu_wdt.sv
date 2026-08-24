`default_nettype none

// A clock-domain-local watchdog.  Expiry latches a software-visible status,
// can raise an interrupt for diagnostics, and can emit a single reset request
// pulse for the platform reset controller.  The system wrapper deliberately
// keeps the reset controller outside this portable peripheral.
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

  localparam logic [5:0] REG_CTRL    = 6'h00;
  localparam logic [5:0] REG_TIMEOUT = 6'h01;
  localparam logic [5:0] REG_FEED    = 6'h02;
  localparam logic [5:0] REG_STATUS  = 6'h03;

  logic        enable_q;
  logic        reset_enable_q;
  logic        irq_enable_q;
  logic [31:0] timeout_q;
  logic [31:0] count_q;
  logic        expired_q;
  logic        reset_req_q;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;
  logic [31:0] timeout_merged;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = expired_q & irq_enable_q;
  assign reset_req_o = reset_req_q;
  assign timeout_merged = `OMCU_MERGE_WRITE(timeout_q, write_data_i, write_strobe_i);

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = reset_enable_q;
    ctrl_read[2] = irq_enable_q;
    status_read = '0;
    status_read[0] = expired_q;
    status_read[1] = reset_req_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:    read_data_o = ctrl_read;
      REG_TIMEOUT: read_data_o = timeout_q;
      REG_STATUS:  read_data_o = status_read;
      default:     read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      reset_enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      timeout_q <= 32'hffff_ffff;
      count_q <= 32'h0000_0000;
      expired_q <= 1'b0;
      reset_req_q <= 1'b0;
    end else begin
      // Reset requests are pulses.  A platform reset sequencer decides how
      // long to hold the full MCU in reset and how to record the reset cause.
      reset_req_q <= 1'b0;

      if (enable_q) begin
        if (count_q >= timeout_q) begin
          count_q <= 32'h0000_0000;
          expired_q <= 1'b1;
          reset_req_q <= reset_enable_q;
        end else begin
          count_q <= count_q + 32'd1;
        end
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: begin
            if (write_strobe_i[0]) begin
              enable_q <= write_data_i[0];
              reset_enable_q <= write_data_i[1];
              irq_enable_q <= write_data_i[2];
              if (!write_data_i[0]) begin
                count_q <= 32'h0000_0000;
              end
            end
          end
          REG_TIMEOUT: begin
            timeout_q <= timeout_merged;
          end
          REG_FEED: begin
            if (`OMCU_MERGE_WRITE(32'h0000_0000, write_data_i, write_strobe_i) == FEED_MAGIC) begin
              count_q <= 32'h0000_0000;
            end
          end
          REG_STATUS: begin
            if (write_strobe_i[0] && write_data_i[0]) begin
              expired_q <= 1'b0;
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
