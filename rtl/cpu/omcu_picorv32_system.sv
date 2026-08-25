`default_nettype none

`ifndef OMCU_PCPI_DIVIDER_INCLUDED
`include "rtl/cpu/omcu_pcpi_divider.sv"
`endif
`default_nettype none

// `$readmemh` is elaborated while Yosys reads this module, before a parent
// module parameter can reliably be changed with `chparam`.  FPGA build flows
// that need a generated application image therefore provide this optional
// compile-time configuration.  It is deliberately generic, so another FPGA
// wrapper can use the same mechanism without depending on Tang-specific RTL.
`ifdef OMCU_ROM_IMAGE_BUILD
`include "omcu_rom_image_config.vh"
`endif

// v1 executable OpenMCU system. PicoRV32 is a deliberately replaceable CPU
// adapter: peripherals see only the portable OpenMCU MMIO contract below.
// The simple ROM/SRAM models are suitable for simulation and an FPGA bring-up
// image. An ASIC implementation replaces them with macro wrappers.
module omcu_picorv32_system #(
  parameter integer GPIO_COUNT = 24,
  parameter integer ROM_WORDS = 1024,
  parameter integer SRAM_BYTES = 32768,
  // The Tang Nano 9K product target maps its separate 608 Kbit user flash at
  // 0x2000_0000. Generic simulation/bring-up builds leave it absent.
  parameter integer USER_FLASH_BYTES = 4,
  parameter integer USER_FLASH_PRESENT = 0,
  parameter integer USER_FLASH_USE_GOWIN_PRIMITIVE = 0,
  parameter integer CLOCK_HZ = 27000000,
  parameter logic [15:0] ABI_MINOR = 16'h0007,
  parameter logic [31:0] FEATURE_BITS = 32'h0000_80ff,
  parameter integer GPIO_EXPANSION_PRESENT = 0,
  parameter integer UART1_PRESENT = 0,
  parameter integer PWM1_PRESENT = 0,
  parameter integer TIMER1_PRESENT = 0,
  parameter integer ALARM0_PRESENT = 0,
  parameter integer PULSE0_PRESENT = 0,
  parameter integer PINMUX_PRESENT = 0,
  parameter integer DIAGNOSTICS_PRESENT = 0,
  // In product-loader mode applications execute from SRAM, so PicoRV32 must
  // enter external interrupts at the application's fixed SRAM vector.
  parameter integer APPLICATION_BOOT_MODE = 0,
`ifdef OMCU_ROM_IMAGE_BUILD
  parameter ROM_INIT_FILE = `OMCU_ROM_IMAGE_FILE
`else
  parameter ROM_INIT_FILE = ""
`endif
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  // Retained by the platform reset sequencer.  They deliberately remain
  // inputs to the portable SoC so an ASIC wrapper can supply equivalent
  // reset-domain retention without importing Tang-specific logic here.
  input  logic [31:0]           reset_cause_i,
  input  logic [31:0]           reset_count_i,
  input  logic                  boot_request_pending_i,
  output logic                  software_boot_request_o,
  output logic                  boot_request_ack_o,

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
  input  logic                  timer1_capture_a_i,
  input  logic                  timer1_capture_b_i,
  output logic                  timer1_irq_o,
  input  logic [2:0]            pulse0_i,
  output logic                  alarm_irq_o,
  output logic                  pulse0_irq_o,
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
  output logic [3:0]            pwm1_o,
  output logic                  pinmux_uart1_enable_o,
  output logic                  pinmux_pwm1_enable_o,
  output logic                  pinmux_timer1_enable_o,
  output logic                  pinmux_pulse0_enable_o,

  output logic                  cpu_trap_o,
  output logic                  bus_error_o
);

  localparam logic [31:0] SRAM_BASE = 32'h1000_0000;
  localparam logic [31:0] SRAM_END = SRAM_BASE + SRAM_BYTES;
  localparam logic [31:0] USER_FLASH_BASE = 32'h2000_0000;
  localparam logic [31:0] USER_FLASH_END = USER_FLASH_BASE + USER_FLASH_BYTES;
  localparam logic [31:0] MMIO_BASE = 32'h4000_0000;
  localparam logic [31:0] MMIO_END = 32'h4001_0000;
  localparam logic [31:0] BOOT_ROM_BYTES = ROM_WORDS * 4;
  localparam logic [31:0] SYSTEM_FEATURE_BITS = FEATURE_BITS |
    ((GPIO_EXPANSION_PRESENT != 0) ? 32'h0000_2000 : 32'h0000_0000) |
    ((UART1_PRESENT != 0) ? 32'h0000_0100 : 32'h0000_0000) |
    ((TIMER1_PRESENT != 0) ? 32'h0000_0200 : 32'h0000_0000) |
    ((PWM1_PRESENT != 0) ? 32'h0000_0400 : 32'h0000_0000) |
    ((ALARM0_PRESENT != 0) ? 32'h0001_0000 : 32'h0000_0000) |
    ((PULSE0_PRESENT != 0) ? 32'h0002_0000 : 32'h0000_0000) |
    ((DIAGNOSTICS_PRESENT != 0) ? 32'h0000_0800 : 32'h0000_0000) |
    ((PINMUX_PRESENT != 0) ? 32'h0000_1000 : 32'h0000_0000) |
    ((USER_FLASH_PRESENT != 0) ? 32'h0000_4000 : 32'h0000_0000);
  localparam logic [31:0] CPU_EXTERNAL_IRQ_BITS = 32'h0000_3f00 |
    ((UART1_PRESENT != 0) ? 32'h0000_4000 : 32'h0000_0000) |
    ((TIMER1_PRESENT != 0) ? 32'h0000_8000 : 32'h0000_0000) |
    ((ALARM0_PRESENT != 0) ? 32'h0001_0000 : 32'h0000_0000) |
    ((PULSE0_PRESENT != 0) ? 32'h0002_0000 : 32'h0000_0000);
  localparam logic [31:0] STACK_ADDRESS = SRAM_BASE + SRAM_BYTES - 4;
  localparam integer ROM_ADDR_BITS = $clog2(ROM_WORDS);
  localparam integer SRAM_WORDS = SRAM_BYTES / 4;
  localparam integer SRAM_ADDR_BITS = $clog2(SRAM_WORDS);

  logic [31:0] boot_rom [0:ROM_WORDS-1];
  logic [31:0] sram [0:SRAM_WORDS-1];

  logic        cpu_mem_valid;
  logic [31:0] cpu_mem_addr;
  logic [31:0] cpu_mem_wdata;
  logic [3:0]  cpu_mem_wstrb;
  logic        cpu_mem_ready;
  logic [31:0] cpu_mem_rdata;

  logic rom_select;
  logic sram_select;
  logic user_flash_select;
  logic mmio_select;
  logic unmapped_select;
  logic [ROM_ADDR_BITS-1:0] rom_word_index;
  logic [SRAM_ADDR_BITS-1:0] sram_word_index;
  logic mmio_ready;
  logic [31:0] mmio_read_data;
  logic mmio_error;
  logic user_flash_ready;
  logic [31:0] user_flash_read_data;
  logic user_flash_error;
  logic [31:0] cpu_irq_vector;
  logic [31:0] cpu_eoi;
  logic        cpu_pcpi_valid;
  logic [31:0] cpu_pcpi_insn;
  logic [31:0] cpu_pcpi_rs1;
  logic [31:0] cpu_pcpi_rs2;
  logic        cpu_pcpi_wr;
  logic [31:0] cpu_pcpi_rd;
  logic        cpu_pcpi_wait;
  logic        cpu_pcpi_ready;

  integer init_index;

  // FPGA bitstream loaders commonly support initialized inferred memories.
  // This is intentionally not an ASIC memory-reset strategy.
  initial begin
`ifndef OMCU_ROM_IMAGE_BUILD
    for (init_index = 0; init_index < ROM_WORDS; init_index = init_index + 1) begin
      boot_rom[init_index] = 32'h0000_0013;  // RISC-V NOP
    end
`endif
    for (init_index = 0; init_index < SRAM_WORDS; init_index = init_index + 1) begin
      sram[init_index] = 32'h0000_0000;
    end
`ifdef OMCU_ROM_IMAGE_BUILD
    // The open FPGA build supplies a padded image, so there is exactly one
    // initializer for boot_rom. Keep its path syntactically literal at the
    // `$readmemh` call site: Yosys lowers memory initialization before a
    // string parameter override is dependable.
    $readmemh(`OMCU_ROM_IMAGE_FILE, boot_rom);
`else
    if (ROM_INIT_FILE != "") begin
      $readmemh(ROM_INIT_FILE, boot_rom);
    end
`endif
  end

  assign rom_select = cpu_mem_valid && (cpu_mem_addr < BOOT_ROM_BYTES);
  assign sram_select = cpu_mem_valid &&
                       (cpu_mem_addr >= SRAM_BASE) &&
                       (cpu_mem_addr < SRAM_END);
  assign user_flash_select = (USER_FLASH_PRESENT != 0) &&
                             cpu_mem_valid &&
                             (cpu_mem_addr >= USER_FLASH_BASE) &&
                             (cpu_mem_addr < USER_FLASH_END);
  assign mmio_select = cpu_mem_valid &&
                       (cpu_mem_addr >= MMIO_BASE) &&
                       (cpu_mem_addr < MMIO_END);
  assign unmapped_select = cpu_mem_valid &&
                            !rom_select && !sram_select && !user_flash_select &&
                            !mmio_select;
  assign rom_word_index = cpu_mem_addr[ROM_ADDR_BITS+1:2];
  assign sram_word_index = cpu_mem_addr[SRAM_ADDR_BITS+1:2];

  // There is no architectural access-fault exception in the minimal v0
  // PicoRV32 adapter. This signal is a diagnostic for simulation and board
  // bring-up; the longer-term CPU/debug adapter will promote it to an error.
  assign bus_error_o = unmapped_select ||
                        (rom_select && (|cpu_mem_wstrb)) ||
                        (user_flash_select && user_flash_error) ||
                        (mmio_select && mmio_error);

  always_ff @(posedge clk_i) begin
    if (sram_select && (|cpu_mem_wstrb)) begin
      sram[sram_word_index] <= `OMCU_MERGE_WRITE(
        sram[sram_word_index],
        cpu_mem_wdata,
        cpu_mem_wstrb
      );
    end
  end

  omcu_mmio_fabric #(
    .GPIO_COUNT(GPIO_COUNT),
    .ROM_BYTES(BOOT_ROM_BYTES),
    .SRAM_BYTES(SRAM_BYTES),
    .ABI_MINOR(ABI_MINOR),
    .FEATURE_BITS(SYSTEM_FEATURE_BITS),
    .UART1_PRESENT(UART1_PRESENT),
    .PWM1_PRESENT(PWM1_PRESENT),
    .TIMER1_PRESENT(TIMER1_PRESENT),
    .ALARM0_PRESENT(ALARM0_PRESENT),
    .PULSE0_PRESENT(PULSE0_PRESENT),
    .PINMUX_PRESENT(PINMUX_PRESENT),
    .BOOT_REQUEST_PRESENT(
      ((APPLICATION_BOOT_MODE != 0) && (USER_FLASH_PRESENT != 0))
    )
  ) mmio (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .reset_cause_i(reset_cause_i),
    .reset_count_i(reset_count_i),
    .boot_request_pending_i(boot_request_pending_i),
    .software_boot_request_o(software_boot_request_o),
    .boot_request_ack_o(boot_request_ack_o),
    .req_i(mmio_select),
    .write_i(|cpu_mem_wstrb),
    .addr_i(cpu_mem_addr),
    .write_data_i(cpu_mem_wdata),
    .write_strobe_i(cpu_mem_wstrb),
    .ready_o(mmio_ready),
    .read_data_o(mmio_read_data),
    .error_o(mmio_error),
    .gpio_in_i(gpio_in_i),
    .gpio_out_o(gpio_out_o),
    .gpio_oe_o(gpio_oe_o),
    .gpio_irq_o(gpio_irq_o),
    .uart_rx_i(uart_rx_i),
    .uart_tx_o(uart_tx_o),
    .uart_irq_o(uart_irq_o),
    .uart1_rx_i(uart1_rx_i),
    .uart1_tx_o(uart1_tx_o),
    .uart1_irq_o(uart1_irq_o),
    .timer_irq_o(timer_irq_o),
    .timer1_capture_a_i(timer1_capture_a_i),
    .timer1_capture_b_i(timer1_capture_b_i),
    .timer1_irq_o(timer1_irq_o),
    .pulse0_i(pulse0_i),
    .alarm_irq_o(alarm_irq_o),
    .pulse0_irq_o(pulse0_irq_o),
    .spi_miso_i(spi_miso_i),
    .spi_mosi_o(spi_mosi_o),
    .spi_sck_o(spi_sck_o),
    .spi_cs_n_o(spi_cs_n_o),
    .spi_irq_o(spi_irq_o),
    .i2c_scl_i(i2c_scl_i),
    .i2c_sda_i(i2c_sda_i),
    .i2c_scl_drive_low_o(i2c_scl_drive_low_o),
    .i2c_sda_drive_low_o(i2c_sda_drive_low_o),
    .i2c_irq_o(i2c_irq_o),
    .wdt_irq_o(wdt_irq_o),
    .wdt_reset_req_o(wdt_reset_req_o),
    .pwm_o(pwm_o),
    .pwm1_o(pwm1_o),
    .pinmux_uart1_enable_o(pinmux_uart1_enable_o),
    .pinmux_pwm1_enable_o(pinmux_pwm1_enable_o),
    .pinmux_timer1_enable_o(pinmux_timer1_enable_o),
    .pinmux_pulse0_enable_o(pinmux_pulse0_enable_o),
    .irq_vector_o(cpu_irq_vector)
  );

  // This window is intentionally independent of the FPGA configuration ROM.
  // In the Tang product target it is backed by GW1NR-9C user flash; a generic
  // behavioral model keeps the same transaction contract available in RTL
  // simulation.
  omcu_user_flash #(
    .FLASH_BYTES(USER_FLASH_BYTES),
    .CLOCK_HZ(CLOCK_HZ),
    .PRESENT(USER_FLASH_PRESENT),
    .USE_GOWIN_USER_FLASH(USER_FLASH_USE_GOWIN_PRIMITIVE)
  ) user_flash (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .req_i(user_flash_select),
    .write_i(|cpu_mem_wstrb),
    .addr_i(cpu_mem_addr - USER_FLASH_BASE),
    .write_data_i(cpu_mem_wdata),
    .write_strobe_i(cpu_mem_wstrb),
    .ready_o(user_flash_ready),
    .read_data_o(user_flash_read_data),
    .error_o(user_flash_error)
  );

  always_comb begin
    cpu_mem_ready = 1'b0;
    cpu_mem_rdata = 32'h0000_0000;

    if (rom_select) begin
      cpu_mem_ready = 1'b1;
      cpu_mem_rdata = boot_rom[rom_word_index];
    end else if (sram_select) begin
      cpu_mem_ready = 1'b1;
      cpu_mem_rdata = sram[sram_word_index];
    end else if (user_flash_select) begin
      cpu_mem_ready = user_flash_ready;
      cpu_mem_rdata = user_flash_read_data;
    end else if (mmio_select) begin
      cpu_mem_ready = mmio_ready;
      cpu_mem_rdata = mmio_read_data;
    end else if (unmapped_select) begin
      // Acknowledge bad accesses so the core cannot deadlock during bring-up.
      cpu_mem_ready = 1'b1;
    end
  end

  omcu_pcpi_divider compact_divider (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
    .pcpi_valid_i(cpu_pcpi_valid),
    .pcpi_insn_i(cpu_pcpi_insn),
    .pcpi_rs1_i(cpu_pcpi_rs1),
    .pcpi_rs2_i(cpu_pcpi_rs2),
    .pcpi_wr_o(cpu_pcpi_wr),
    .pcpi_rd_o(cpu_pcpi_rd),
    .pcpi_wait_o(cpu_pcpi_wait),
    .pcpi_ready_o(cpu_pcpi_ready)
  );

  picorv32 #(
    // Product diagnostics exposes a retained reset record and a coherent
    // SYSCTRL run-tick counter. Omitting PicoRV32's duplicate cycle/instret
    // CSRs preserves LUT headroom for the P1 peripheral profile.
    .ENABLE_COUNTERS(1'b0),
    .ENABLE_COUNTERS64(1'b0),
    .ENABLE_REGS_16_31(1'b1),
    // One read port trades a small number of extra core cycles for the LUT
    // headroom needed by the complete, physically routable P0/P1 MCU profile.
    // It does not change the RV32IMC ISA or the firmware ABI.
    .ENABLE_REGS_DUALPORT(1'b0),
    .LATCHED_MEM_RDATA(1'b0),
    // A compact iterative shifter leaves enough fabric for the complete P1
    // peripheral profile. Shift instructions remain part of RV32IMC; only
    // their worst-case execution latency increases.
    .TWO_STAGE_SHIFT(1'b0),
    .BARREL_SHIFTER(1'b0),
    .TWO_CYCLE_COMPARE(1'b0),
    .TWO_CYCLE_ALU(1'b0),
    .COMPRESSED_ISA(1'b1),
    .CATCH_MISALIGN(1'b1),
    .CATCH_ILLINSN(1'b1),
    .ENABLE_PCPI(1'b1),
    .ENABLE_MUL(1'b0),
    .ENABLE_FAST_MUL(1'b1),
    .ENABLE_DIV(1'b0),
    .ENABLE_IRQ(1'b1),
    .ENABLE_IRQ_QREGS(1'b1),
    .ENABLE_IRQ_TIMER(1'b0),
    // Bits 0..2 are PicoRV32-reserved; the portable IRQ controller owns bits
    // 8..13 plus, when advertised, UART1 at bit 14 and TIMER1 at bit 15.
    // Everything else is masked.
    .MASKED_IRQ(~CPU_EXTERNAL_IRQ_BITS),
    .LATCHED_IRQ(CPU_EXTERNAL_IRQ_BITS),
    .ENABLE_TRACE(1'b0),
    .PROGADDR_RESET(32'h0000_0000),
    .PROGADDR_IRQ(
      APPLICATION_BOOT_MODE ? (SRAM_BASE + 32'h0000_0010) : 32'h0000_0010
    ),
    .STACKADDR(STACK_ADDRESS)
  ) cpu (
    .clk(clk_i),
    .resetn(rst_ni),
    .trap(cpu_trap_o),
    .mem_valid(cpu_mem_valid),
    .mem_instr(),
    .mem_ready(cpu_mem_ready),
    .mem_addr(cpu_mem_addr),
    .mem_wdata(cpu_mem_wdata),
    .mem_wstrb(cpu_mem_wstrb),
    .mem_rdata(cpu_mem_rdata),
    .mem_la_read(),
    .mem_la_write(),
    .mem_la_addr(),
    .mem_la_wdata(),
    .mem_la_wstrb(),
    .pcpi_valid(cpu_pcpi_valid),
    .pcpi_insn(cpu_pcpi_insn),
    .pcpi_rs1(cpu_pcpi_rs1),
    .pcpi_rs2(cpu_pcpi_rs2),
    .pcpi_wr(cpu_pcpi_wr),
    .pcpi_rd(cpu_pcpi_rd),
    .pcpi_wait(cpu_pcpi_wait),
    .pcpi_ready(cpu_pcpi_ready),
    .irq(cpu_irq_vector),
    .eoi(cpu_eoi),
    .trace_valid(),
    .trace_data()
  );

endmodule

`default_nettype wire
