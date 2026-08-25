`default_nettype none

// Logic-level hardware fault interlock for the reviewed FPGA profile.
//
// FAULT0 synchronizes and optionally filters one explicitly pinmux-claimed
// input, latches the first active state, requests a shared GPIO diagnostic
// snapshot, and can force PWM outputs low and every reviewed GPIO
// output-enable to high impedance. It is not a
// certified functional-safety block, an asynchronous emergency shutoff, or a
// substitute for an external power-stage interlock.
module omcu_fault #(
  parameter integer GPIO_COUNT = 24,
  parameter logic [31:0] CLEAR_MAGIC = 32'hfa17_c1ea
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

  input  logic                  fault_i,
  input  logic                  input_claim_i,
  // These are the context registers held by GPIO0. On a fault trip this
  // block forces a priority capture, so FAULT0 and GPIO0 report one coherent
  // first-trip record without duplicating four wide state banks.
  input  logic [31:0]           snapshot_tick_i,
  input  logic [31:0]           snapshot_gpio_i,
  input  logic [31:0]           snapshot_irq_i,
  input  logic [31:0]           snapshot_reset_i,

  output logic                  irq_o,
  output logic                  snapshot_trigger_o,
  output logic                  trip_o,
  output logic                  pwm0_kill_o,
  output logic                  pwm1_kill_o,
  output logic [GPIO_COUNT-1:0] gpio_hiz_mask_o
);

  localparam logic [5:0] REG_CTRL          = 6'h00;
  localparam logic [5:0] REG_FILTER        = 6'h01;
  localparam logic [5:0] REG_GPIO_HIZ_MASK = 6'h02;
  localparam logic [5:0] REG_STATUS        = 6'h03;
  localparam logic [5:0] REG_CLEAR         = 6'h04;
  localparam logic [5:0] REG_SNAPSHOT_TICK = 6'h05;
  localparam logic [5:0] REG_SNAPSHOT_GPIO = 6'h06;
  localparam logic [5:0] REG_SNAPSHOT_IRQ  = 6'h07;
  localparam logic [5:0] REG_SNAPSHOT_RESET = 6'h08;

  logic enable_q;
  logic active_high_q;
  logic irq_enable_q;
  logic gate_pwm0_q;
  logic gate_pwm1_q;
  logic gate_gpio_q;
  logic [7:0] filter_q;
  logic fault_meta_q;
  logic fault_sync_q;
  logic fault_filtered_q;
  logic [7:0] filter_count_q;
  logic trip_q;
  logic clear_rejected_q;

  logic filter_accept;
  logic fault_filtered_next;
  logic fault_active_q;
  logic fault_active_next;
  logic trip_event;
  logic clear_command;
  logic clear_allowed;
  logic full_word_write;
  logic [31:0] gpio_hiz_profile_ext;
  logic [31:0] ctrl_read;
  logic [31:0] status_read;

  assign ready_o = req_i;
  assign error_o = 1'b0;
  assign irq_o = trip_q && irq_enable_q;
  assign snapshot_trigger_o = trip_event;
  assign trip_o = trip_q;
  assign pwm0_kill_o = trip_q && gate_pwm0_q;
  assign pwm1_kill_o = trip_q && gate_pwm1_q;
  // A fault gate is deliberately a fixed, conservative profile: once armed
  // it releases every reviewed GPIO pad rather than leaving a software-chosen
  // subset driving. This also avoids a wide configuration mux on the safety
  // path in the small FPGA.
  assign gpio_hiz_mask_o = (trip_q && gate_gpio_q) ? {GPIO_COUNT{1'b1}} : '0;
  assign filter_accept = (fault_sync_q != fault_filtered_q) &&
                         (filter_count_q == filter_q);
  assign fault_filtered_next = filter_accept ? fault_sync_q : fault_filtered_q;
  assign fault_active_q = active_high_q ? fault_filtered_q : ~fault_filtered_q;
  assign fault_active_next = active_high_q ? fault_filtered_next : ~fault_filtered_next;
  assign trip_event = enable_q && input_claim_i && fault_active_next && !trip_q;
  assign clear_command = req_i && write_i && (addr_i[7:2] == REG_CLEAR) &&
                         (write_strobe_i == 4'b1111) &&
                         (write_data_i == CLEAR_MAGIC);
  // MMIO configuration and command registers use an atomic 32-bit write
  // contract.  A byte/halfword store must not arm, disarm, or otherwise
  // weaken a hardware fault interlock by changing only part of its state.
  assign full_word_write = write_strobe_i == 4'b1111;
  // Software cannot clear a latched fault merely by releasing its pinmux
  // claim. The reviewed input must remain claimed and inactive.
  assign clear_allowed = clear_command && input_claim_i && !fault_active_next;
  always_comb begin
    gpio_hiz_profile_ext = '0;
    gpio_hiz_profile_ext[GPIO_COUNT-1:0] = {GPIO_COUNT{1'b1}};

    ctrl_read = '0;
    ctrl_read[0] = enable_q;
    ctrl_read[1] = active_high_q;
    ctrl_read[2] = irq_enable_q;
    ctrl_read[3] = gate_pwm0_q;
    ctrl_read[4] = gate_pwm1_q;
    ctrl_read[5] = gate_gpio_q;
    status_read = '0;
    status_read[0] = trip_q;
    status_read[1] = fault_filtered_q;
    status_read[2] = input_claim_i;
    status_read[3] = clear_rejected_q;
    status_read[4] = fault_active_q;

    read_data_o = '0;
    unique case (addr_i[7:2])
      REG_CTRL:           read_data_o = ctrl_read;
      REG_FILTER:         read_data_o = {24'h000000, filter_q};
      REG_GPIO_HIZ_MASK:  read_data_o = gpio_hiz_profile_ext;
      REG_STATUS:         read_data_o = status_read;
      REG_SNAPSHOT_TICK:  read_data_o = snapshot_tick_i;
      REG_SNAPSHOT_GPIO:  read_data_o = snapshot_gpio_i;
      REG_SNAPSHOT_IRQ:   read_data_o = snapshot_irq_i;
      REG_SNAPSHOT_RESET: read_data_o = snapshot_reset_i;
      default:            read_data_o = '0;
    endcase
  end

  always_ff @(posedge clk_i or negedge rst_ni) begin
    if (!rst_ni) begin
      enable_q <= 1'b0;
      active_high_q <= 1'b1;
      irq_enable_q <= 1'b0;
      gate_pwm0_q <= 1'b0;
      gate_pwm1_q <= 1'b0;
      gate_gpio_q <= 1'b0;
      filter_q <= 8'h00;
      fault_meta_q <= 1'b0;
      fault_sync_q <= 1'b0;
      fault_filtered_q <= 1'b0;
      filter_count_q <= 8'h00;
      trip_q <= 1'b0;
      clear_rejected_q <= 1'b0;
    end else begin
      fault_meta_q <= fault_i;
      fault_sync_q <= fault_meta_q;
      if (fault_sync_q == fault_filtered_q) begin
        filter_count_q <= 8'h00;
      end else if (filter_accept) begin
        fault_filtered_q <= fault_filtered_next;
        filter_count_q <= 8'h00;
      end else begin
        filter_count_q <= filter_count_q + 8'd1;
      end

      if (trip_event) begin
        trip_q <= 1'b1;
      end
      if (clear_allowed) begin
        trip_q <= trip_event;
      end else if (clear_command && !trip_event) begin
        clear_rejected_q <= 1'b1;
      end

      if (req_i && write_i) begin
        unique case (addr_i[7:2])
          REG_CTRL: if (full_word_write) begin
            enable_q <= write_data_i[0];
            active_high_q <= write_data_i[1];
            irq_enable_q <= write_data_i[2];
            gate_pwm0_q <= write_data_i[3];
            gate_pwm1_q <= write_data_i[4];
            gate_gpio_q <= write_data_i[5];
          end
          REG_FILTER: if (full_word_write) begin
            filter_q <= write_data_i[7:0];
            filter_count_q <= 8'h00;
          end
          REG_STATUS: if (full_word_write && write_data_i[3]) begin
            clear_rejected_q <= 1'b0;
          end
          default: begin
          end
        endcase
      end
    end
  end

endmodule

`default_nettype wire
