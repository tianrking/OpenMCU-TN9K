`default_nettype none

// First-stage decoder for portable OpenMCU MMIO blocks. CPU, ROM/SRAM and XIP
// adapters connect above this fabric; this module deliberately has no CPU- or
// FPGA-vendor-specific ports.
module omcu_mmio_fabric #(
  parameter integer GPIO_COUNT = 24,
  parameter integer ROM_BYTES = 4096,
  parameter integer SRAM_BYTES = 32768,
  parameter logic [15:0] ABI_MINOR = 16'h0006,
  parameter logic [31:0] FEATURE_BITS = 32'h0000_00ff,
  parameter integer UART1_PRESENT = 0,
  parameter integer PINMUX_PRESENT = 0
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
  input  logic                  uart1_rx_i,
  output logic                  uart1_tx_o,
  output logic                  uart1_irq_o,
  output logic                  timer_irq_o,

  input  logic                  spi_miso_i,
  output logic                  spi_mosi_o,
  output logic                  spi_sck_o,
  output logic                  spi_cs_n_o,
  output logic                  spi_irq_o,
  input  logic                  i2c_scl_i,
  input  logic                  i2c_sda_i,
  output logic                  i2c_scl_drive_low_o,
  output logic                  i2c_sda_drive_low_o,
  output logic                  i2c_irq_o,
  output logic                  wdt_irq_o,
  output logic                  wdt_reset_req_o,
  output logic                  pwm_o,
  output logic                  pinmux_uart1_enable_o,
  output logic                  pinmux_pwm1_enable_o,
  output logic                  pinmux_timer1_enable_o,
  output logic [31:0]           irq_vector_o
);

  localparam logic [19:0] GPIO0_PAGE  = 20'h40000;
  localparam logic [19:0] UART0_PAGE  = 20'h40001;
  localparam logic [19:0] TIMER0_PAGE = 20'h40002;
  localparam logic [19:0] SPI0_PAGE   = 20'h40003;
  localparam logic [19:0] I2C0_PAGE   = 20'h40004;
  localparam logic [19:0] WDT0_PAGE   = 20'h40005;
  localparam logic [19:0] PWM0_PAGE   = 20'h40006;
  localparam logic [19:0] IRQCTRL_PAGE = 20'h40007;
  localparam logic [19:0] UART1_PAGE  = 20'h40008;
  localparam logic [19:0] PINMUX_PAGE = 20'h4000b;
  localparam logic [19:0] SYSCTRL_PAGE = 20'h4000f;
  localparam integer IRQ_SOURCE_COUNT = (UART1_PRESENT != 0) ? 7 : 6;

  logic gpio_select;
  logic uart_select;
  logic uart1_select;
  logic timer_select;
  logic spi_select;
  logic i2c_select;
  logic wdt_select;
  logic pwm_select;
  logic irqctrl_select;
  logic pinmux_select;
  logic sysctrl_select;
  logic gpio_ready;
  logic uart_ready;
  logic uart1_ready;
  logic timer_ready;
  logic spi_ready;
  logic i2c_ready;
  logic wdt_ready;
  logic pwm_ready;
  logic irqctrl_ready;
  logic pinmux_ready;
  logic sysctrl_ready;
  logic [31:0] gpio_read_data;
  logic [31:0] uart_read_data;
  logic [31:0] uart1_read_data;
  logic [31:0] timer_read_data;
  logic [31:0] spi_read_data;
  logic [31:0] i2c_read_data;
  logic [31:0] wdt_read_data;
  logic [31:0] pwm_read_data;
  logic [31:0] irqctrl_read_data;
  logic [31:0] pinmux_read_data;
  logic [31:0] sysctrl_read_data;
  logic [7:0] irq_sources;

  assign gpio_select = req_i && (addr_i[31:12] == GPIO0_PAGE);
  assign uart_select = req_i && (addr_i[31:12] == UART0_PAGE);
  assign uart1_select = (UART1_PRESENT != 0) && req_i &&
                        (addr_i[31:12] == UART1_PAGE);
  assign timer_select = req_i && (addr_i[31:12] == TIMER0_PAGE);
  assign spi_select = req_i && (addr_i[31:12] == SPI0_PAGE);
  assign i2c_select = req_i && (addr_i[31:12] == I2C0_PAGE);
  assign wdt_select = req_i && (addr_i[31:12] == WDT0_PAGE);
  assign pwm_select = req_i && (addr_i[31:12] == PWM0_PAGE);
  assign irqctrl_select = req_i && (addr_i[31:12] == IRQCTRL_PAGE);
  assign pinmux_select = (PINMUX_PRESENT != 0) && req_i &&
                         (addr_i[31:12] == PINMUX_PAGE);
  assign sysctrl_select = req_i && (addr_i[31:12] == SYSCTRL_PAGE);

  // Keep this source ordering stable: the IRQ controller maps element zero to
  // CPU IRQ 8 and advertises the exact resulting masks in the SDK register
  // specification.  New sources belong at the end of the array.
  assign irq_sources[0] = gpio_irq_o;
  assign irq_sources[1] = uart_irq_o;
  assign irq_sources[2] = timer_irq_o;
  assign irq_sources[3] = spi_irq_o;
  assign irq_sources[4] = i2c_irq_o;
  assign irq_sources[5] = wdt_irq_o;
  assign irq_sources[6] = uart1_irq_o;
  assign irq_sources[7] = 1'b0;

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

  omcu_uart uart1 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(uart1_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(uart1_ready),
    .read_data_o(uart1_read_data),
    .error_o(),
    .rx_i(uart1_rx_i),
    .tx_o(uart1_tx_o),
    .irq_o(uart1_irq_o)
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

  omcu_spi spi0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(spi_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(spi_ready),
    .read_data_o(spi_read_data),
    .error_o(),
    .miso_i(spi_miso_i),
    .mosi_o(spi_mosi_o),
    .sck_o(spi_sck_o),
    .cs_n_o(spi_cs_n_o),
    .irq_o(spi_irq_o)
  );

  omcu_i2c i2c0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(i2c_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(i2c_ready),
    .read_data_o(i2c_read_data),
    .error_o(),
    .scl_i(i2c_scl_i),
    .sda_i(i2c_sda_i),
    .scl_drive_low_o(i2c_scl_drive_low_o),
    .sda_drive_low_o(i2c_sda_drive_low_o),
    .irq_o(i2c_irq_o)
  );

  omcu_wdt wdt0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(wdt_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(wdt_ready),
    .read_data_o(wdt_read_data),
    .error_o(),
    .irq_o(wdt_irq_o),
    .reset_req_o(wdt_reset_req_o)
  );

  omcu_pwm pwm0 (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(pwm_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(pwm_ready),
    .read_data_o(pwm_read_data),
    .error_o(),
    .pwm_o(pwm_o)
  );

  omcu_irq_ctrl #(
    .SOURCE_COUNT(IRQ_SOURCE_COUNT),
    .IRQ_BASE(8)
  ) irqctrl (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(irqctrl_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(irqctrl_ready),
    .read_data_o(irqctrl_read_data),
    .error_o(),
    .source_i(irq_sources[IRQ_SOURCE_COUNT-1:0]),
    .irq_o(irq_vector_o)
  );

  omcu_pinmux pinmux (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(pinmux_select),
    .write_i(write_i),
    .addr_i(addr_i),
    .write_data_i(write_data_i),
    .write_strobe_i(write_strobe_i),
    .ready_o(pinmux_ready),
    .read_data_o(pinmux_read_data),
    .error_o(),
    .uart1_enable_o(pinmux_uart1_enable_o),
    .pwm1_enable_o(pinmux_pwm1_enable_o),
    .timer1_enable_o(pinmux_timer1_enable_o)
  );

  omcu_sysctrl #(
    .ROM_BYTES(ROM_BYTES),
    .SRAM_BYTES(SRAM_BYTES),
    .ABI_MINOR(ABI_MINOR),
    .FEATURE_BITS(FEATURE_BITS)
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
    end else if (uart1_select) begin
      ready_o = uart1_ready;
      read_data_o = uart1_read_data;
    end else if (timer_select) begin
      ready_o = timer_ready;
      read_data_o = timer_read_data;
    end else if (spi_select) begin
      ready_o = spi_ready;
      read_data_o = spi_read_data;
    end else if (i2c_select) begin
      ready_o = i2c_ready;
      read_data_o = i2c_read_data;
    end else if (wdt_select) begin
      ready_o = wdt_ready;
      read_data_o = wdt_read_data;
    end else if (pwm_select) begin
      ready_o = pwm_ready;
      read_data_o = pwm_read_data;
    end else if (irqctrl_select) begin
      ready_o = irqctrl_ready;
      read_data_o = irqctrl_read_data;
    end else if (pinmux_select) begin
      ready_o = pinmux_ready;
      read_data_o = pinmux_read_data;
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
