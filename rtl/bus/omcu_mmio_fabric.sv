`default_nettype none

// First-stage decoder for portable OpenMCU MMIO blocks. CPU, ROM/SRAM and XIP
// adapters connect above this fabric; this module deliberately has no CPU- or
// FPGA-vendor-specific ports.
module omcu_mmio_fabric #(
  parameter integer GPIO_COUNT = 24,
  parameter integer ROM_BYTES = 4096,
  parameter integer SRAM_BYTES = 32768
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
  output logic                  gpio_irq_o,
  input  logic                  uart_rx_i,
  output logic                  uart_tx_o,
  output logic                  uart_irq_o,
  output logic                  timer_irq_o
);

  localparam logic [19:0] GPIO0_PAGE  = 20'h40000;
  localparam logic [19:0] UART0_PAGE  = 20'h40001;
  localparam logic [19:0] TIMER0_PAGE = 20'h40002;
  localparam logic [19:0] SYSCTRL_PAGE = 20'h4000f;

  logic gpio_select;
  logic uart_select;
  logic timer_select;
  logic sysctrl_select;
  logic gpio_ready;
  logic uart_ready;
  logic timer_ready;
  logic sysctrl_ready;
  logic [31:0] gpio_read_data;
  logic [31:0] uart_read_data;
  logic [31:0] timer_read_data;
  logic [31:0] sysctrl_read_data;

  assign gpio_select = req_i && (addr_i[31:12] == GPIO0_PAGE);
  assign uart_select = req_i && (addr_i[31:12] == UART0_PAGE);
  assign timer_select = req_i && (addr_i[31:12] == TIMER0_PAGE);
  assign sysctrl_select = req_i && (addr_i[31:12] == SYSCTRL_PAGE);

  omcu_gpio #(
    .GPIO_COUNT(GPIO_COUNT)
  ) gpio0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(gpio_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(gpio_ready),
    .read_data_o(gpio_read_data),
    .error_o(),
    .gpio_in_i(gpio_in_i),
    .gpio_out_o(gpio_out_o),
    .gpio_oe_o(gpio_oe_o),
    .irq_o(gpio_irq_o)
  );

  omcu_uart uart0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(uart_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(uart_ready),
    .read_data_o(uart_read_data),
    .error_o(),
    .rx_i(uart_rx_i),
    .tx_o(uart_tx_o),
    .irq_o(uart_irq_o)
  );

  omcu_timer timer0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(timer_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(timer_ready),
    .read_data_o(timer_read_data),
    .error_o(),
    .irq_o(timer_irq_o)
  );

  omcu_sysctrl #(
    .ROM_BYTES(ROM_BYTES),
    .SRAM_BYTES(SRAM_BYTES)
  ) sysctrl (
    .req_i(sysctrl_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .ready_o(sysctrl_ready),
    .read_data_o(sysctrl_read_data),
    .error_o()
  );

  always_comb begin
    ready_o = 1'b0;
    read_data_o = '0;
    error_o = 1'b0;

    if (gpio_select) begin
      ready_o = gpio_ready;
      read_data_o = gpio_read_data;
    end else if (uart_select) begin
      ready_o = uart_ready;
      read_data_o = uart_read_data;
    end else if (timer_select) begin
      ready_o = timer_ready;
      read_data_o = timer_read_data;
    end else if (sysctrl_select) begin
      ready_o = sysctrl_ready;
      read_data_o = sysctrl_read_data;
    end else if (req_i) begin
      // A decoded error makes software integration mistakes visible early.
      ready_o = 1'b1;
      error_o = 1'b1;
    end
  end

endmodule

`default_nettype wire
