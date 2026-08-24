`default_nettype none

// Portable GPIO block for the OpenMCU single-master MMIO contract.
// All register offsets are relative to the GPIO base address.
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

  input  logic [GPIO_COUNT-1:0] gpio_in_i,
  output logic [GPIO_COUNT-1:0] gpio_out_o,
  output logic [GPIO_COUNT-1:0] gpio_oe_o,
  output logic                  irq_o
);

  import omcu_mmio_pkg::*;

  localparam logic [5:0] REG_OUT        = 6'h00;
  localparam logic [5:0] REG_OUT_SET    = 6'h01;
  localparam logic [5:0] REG_OUT_CLR    = 6'h02;
  localparam logic [5:0] REG_OUT_XOR    = 6'h03;
  localparam logic [5:0] REG_OE         = 6'h04;
  localparam logic [5:0] REG_OE_SET     = 6'h05;
  localparam logic [5:0] REG_OE_CLR     = 6'h06;
  localparam logic [5:0] REG_IN         = 6'h08;
  localparam logic [5:0] REG_RISE_EN    = 6'h09;
  localparam logic [5:0] REG_FALL_EN    = 6'h0a;
  localparam logic [5:0] REG_IRQ_STATUS = 6'h0b;

  logic [GPIO_COUNT-1:0] gpio_out_q;
  logic [GPIO_COUNT-1:0] gpio_oe_q;
  logic [GPIO_COUNT-1:0] gpio_in_previous_q;
  logic [GPIO_COUNT-1:0] rise_enable_q;
  logic [GPIO_COUNT-1:0] fall_enable_q;
  logic [GPIO_COUNT-1:0] irq_status_q;

  logic [31:0] gpio_out_ext;
  logic [31:0] gpio_oe_ext;
  logic [31:0] gpio_in_ext;
  logic [31:0] rise_enable_ext;
  logic [31:0] fall_enable_ext;
  logic [31:0] irq_status_ext;
  logic [31:0] write_masked_data;
  logic [31:0] gpio_out_merged;
  logic [31:0] gpio_oe_merged;
  logic [31:0] rise_enable_merged;
  logic [31:0] fall_enable_merged;
  logic [GPIO_COUNT-1:0] irq_events;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign gpio_out_o = gpio_out_q;
  assign gpio_oe_o = gpio_oe_q;
  assign irq_o = |irq_status_q;
  assign write_masked_data = write_data_i & write_strobe_mask(write_strobe_i);
  assign gpio_out_merged = merge_write(gpio_out_ext, write_data_i, write_strobe_i);
  assign gpio_oe_merged = merge_write(gpio_oe_ext, write_data_i, write_strobe_i);
  assign rise_enable_merged = merge_write(rise_enable_ext, write_data_i, write_strobe_i);
  assign fall_enable_merged = merge_write(fall_enable_ext, write_data_i, write_strobe_i);
  assign irq_events = ((gpio_in_i & ~gpio_in_previous_q) & rise_enable_q) |
                      ((~gpio_in_i & gpio_in_previous_q) & fall_enable_q);

  always_comb begin
    gpio_out_ext = '0;
    gpio_oe_ext = '0;
    gpio_in_ext = '0;
    rise_enable_ext = '0;
    fall_enable_ext = '0;
    irq_status_ext = '0;
    gpio_out_ext[GPIO_COUNT-1:0] = gpio_out_q;
    gpio_oe_ext[GPIO_COUNT-1:0] = gpio_oe_q;
    gpio_in_ext[GPIO_COUNT-1:0] = gpio_in_i;
    rise_enable_ext[GPIO_COUNT-1:0] = rise_enable_q;
    fall_enable_ext[GPIO_COUNT-1:0] = fall_enable_q;
    irq_status_ext[GPIO_COUNT-1:0] = irq_status_q;
  end

  always_comb begin
    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_OUT,
      REG_OUT_SET,
      REG_OUT_CLR,
      REG_OUT_XOR:    read_data_o = gpio_out_ext;
      REG_OE,
      REG_OE_SET,
      REG_OE_CLR:     read_data_o = gpio_oe_ext;
      REG_IN:          read_data_o = gpio_in_ext;
      REG_RISE_EN:     read_data_o = rise_enable_ext;
      REG_FALL_EN:     read_data_o = fall_enable_ext;
      REG_IRQ_STATUS:  read_data_o = irq_status_ext;
      default:          read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      gpio_out_q <= '0;
      gpio_oe_q <= '0;
      gpio_in_previous_q <= '0;
      rise_enable_q <= '0;
      fall_enable_q <= '0;
      irq_status_q <= '0;
    end else begin
      gpio_in_previous_q <= gpio_in_i;
      irq_status_q <= irq_status_q | irq_events;

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_OUT: begin
            gpio_out_q <= gpio_out_merged[GPIO_COUNT-1:0];
          end
          REG_OUT_SET: begin
            gpio_out_q <= gpio_out_q | write_masked_data[GPIO_COUNT-1:0];
          end
          REG_OUT_CLR: begin
            gpio_out_q <= gpio_out_q & ~write_masked_data[GPIO_COUNT-1:0];
          end
          REG_OUT_XOR: begin
            gpio_out_q <= gpio_out_q ^ write_masked_data[GPIO_COUNT-1:0];
          end
          REG_OE: begin
            gpio_oe_q <= gpio_oe_merged[GPIO_COUNT-1:0];
          end
          REG_OE_SET: begin
            gpio_oe_q <= gpio_oe_q | write_masked_data[GPIO_COUNT-1:0];
          end
          REG_OE_CLR: begin
            gpio_oe_q <= gpio_oe_q & ~write_masked_data[GPIO_COUNT-1:0];
          end
          REG_RISE_EN: begin
            rise_enable_q <= rise_enable_merged[GPIO_COUNT-1:0];
          end
          REG_FALL_EN: begin
            fall_enable_q <= fall_enable_merged[GPIO_COUNT-1:0];
          end
          REG_IRQ_STATUS: begin
            // Write-one-to-clear. An edge arriving in this cycle wins over a clear.
            irq_status_q <= (irq_status_q & ~write_masked_data[GPIO_COUNT-1:0]) | irq_events;
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
