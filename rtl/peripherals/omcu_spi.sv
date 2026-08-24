`default_nettype none

// A compact, polling-friendly SPI mode-0 master.  One START command transfers
// exactly one byte MSB first while automatically asserting one active-low chip
// select.  A FIFO/QSPI/XIP controller belongs above this predictable byte
// engine; it must not change this public register contract.
module omcu_spi (
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

  input  logic        miso_i,
  output logic        mosi_o,
  output logic        sck_o,
  output logic        cs_n_o,
  output logic        irq_o
);

  import omcu_mmio_pkg::*;

  localparam logic [5:0] REG_DATA   = 6'h00;
  localparam logic [5:0] REG_STATUS = 6'h01;
  localparam logic [5:0] REG_CLKDIV = 6'h02;
  localparam logic [5:0] REG_CTRL   = 6'h03;
  localparam logic [5:0] REG_START  = 6'h04;

  logic        enable_q;
  logic        irq_enable_q;
  logic        busy_q;
  logic        done_q;
  logic [15:0] clkdiv_q;
  logic [15:0] div_count_q;
  logic [7:0]  tx_data_q;
  logic [7:0]  rx_data_q;
  logic [7:0]  tx_shift_q;
  logic [7:0]  rx_shift_q;
  logic [2:0]  bit_index_q;
  logic        sck_q;
  logic        mosi_q;
  logic        cs_n_q;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;
  logic [31:0] clkdiv_merged;
  logic [31:0] tx_data_merged;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = done_q & irq_enable_q;
  assign mosi_o = mosi_q;
  assign sck_o = busy_q ? sck_q : 1'b0;
  assign cs_n_o = cs_n_q;
  assign clkdiv_merged = merge_write({16'h0000, clkdiv_q}, write_data_i, write_strobe_i);
  assign tx_data_merged = merge_write({24'h000000, tx_data_q}, write_data_i, write_strobe_i);

  always_comb begin
    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = irq_enable_q;
    status_read = '0;
    status_read[0] = busy_q;
    status_read[1] = done_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_DATA:   read_data_o = {24'h000000, rx_data_q};
      REG_STATUS: read_data_o = status_read;
      REG_CLKDIV: read_data_o = {16'h0000, clkdiv_q};
      REG_CTRL:   read_data_o = ctrl_read;
      default:    read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      irq_enable_q <= 1'b0;
      busy_q <= 1'b0;
      done_q <= 1'b0;
      clkdiv_q <= 16'd134;
      div_count_q <= 16'h0000;
      tx_data_q <= 8'h00;
      rx_data_q <= 8'h00;
      tx_shift_q <= 8'h00;
      rx_shift_q <= 8'h00;
      bit_index_q <= 3'd0;
      sck_q <= 1'b0;
      mosi_q <= 1'b0;
      cs_n_q <= 1'b1;
    end else begin
      // Mode 0: drive the next MOSI bit while SCK is low, sample MISO on
      // SCK's rising edge, and finish the byte on the final falling edge.
      if (busy_q) begin
        if (div_count_q == clkdiv_q) begin
          div_count_q <= 16'h0000;
          if (!sck_q) begin
            sck_q <= 1'b1;
            rx_shift_q <= {rx_shift_q[6:0], miso_i};
          end else begin
            sck_q <= 1'b0;
            if (bit_index_q == 3'd7) begin
              busy_q <= 1'b0;
              done_q <= 1'b1;
              cs_n_q <= 1'b1;
              rx_data_q <= rx_shift_q;
            end else begin
              bit_index_q <= bit_index_q + 3'd1;
              mosi_q <= tx_shift_q[7];
              tx_shift_q <= {tx_shift_q[6:0], 1'b0};
            end
          end
        end else begin
          div_count_q <= div_count_q + 16'd1;
        end
      end else begin
        div_count_q <= 16'h0000;
        sck_q <= 1'b0;
        cs_n_q <= 1'b1;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_DATA: begin
            tx_data_q <= tx_data_merged[7:0];
          end
          REG_STATUS: begin
            if (write_strobe_i[0] && write_data_i[1]) begin
              done_q <= 1'b0;
            end
          end
          REG_CLKDIV: begin
            clkdiv_q <= clkdiv_merged[15:0];
          end
          REG_CTRL: begin
            if (write_strobe_i[0]) begin
              enable_q <= write_data_i[0];
              irq_enable_q <= write_data_i[1];
              if (!write_data_i[0]) begin
                busy_q <= 1'b0;
                sck_q <= 1'b0;
                cs_n_q <= 1'b1;
              end
            end
          end
          REG_START: begin
            if (write_strobe_i[0] && write_data_i[0] && enable_q && !busy_q) begin
              busy_q <= 1'b1;
              done_q <= 1'b0;
              div_count_q <= 16'h0000;
              bit_index_q <= 3'd0;
              sck_q <= 1'b0;
              cs_n_q <= 1'b0;
              mosi_q <= tx_data_q[7];
              tx_shift_q <= {tx_data_q[6:0], 1'b0};
              rx_shift_q <= 8'h00;
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
