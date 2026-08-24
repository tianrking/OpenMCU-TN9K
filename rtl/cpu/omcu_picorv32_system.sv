`default_nettype none

// v0 executable OpenMCU system. PicoRV32 is a deliberately replaceable CPU
// adapter: peripherals see only the portable OpenMCU MMIO contract below.
// The simple ROM/SRAM models are suitable for simulation and an FPGA bring-up
// image. An ASIC implementation replaces them with macro wrappers.
module omcu_picorv32_system #(
  parameter integer GPIO_COUNT = 24,
  parameter integer ROM_WORDS = 1024,
  parameter integer SRAM_BYTES = 32768,
  parameter ROM_INIT_FILE = ""
) (
  input  logic                  clk_i,
  input  logic                  rst_ni,

  input  logic [GPIO_COUNT-1:0] gpio_in_i,
  output logic [GPIO_COUNT-1:0] gpio_out_o,
  output logic [GPIO_COUNT-1:0] gpio_oe_o,
  output logic                  gpio_irq_o,
  input  logic                  uart_rx_i,
  output logic                  uart_tx_o,
  output logic                  uart_irq_o,
  output logic                  timer_irq_o,

  output logic                  cpu_trap_o,
  output logic                  bus_error_o
);

  import omcu_mmio_pkg::*;

  localparam logic [31:0] SRAM_BASE = 32'h1000_0000;
  localparam logic [31:0] SRAM_END = SRAM_BASE + SRAM_BYTES;
  localparam logic [31:0] MMIO_BASE = 32'h4000_0000;
  localparam logic [31:0] MMIO_END = 32'h4001_0000;
  localparam logic [31:0] BOOT_ROM_BYTES = ROM_WORDS * 4;
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
  logic mmio_select;
  logic unmapped_select;
  logic [ROM_ADDR_BITS-1:0] rom_word_index;
  logic [SRAM_ADDR_BITS-1:0] sram_word_index;
  logic mmio_ready;
  logic [31:0] mmio_read_data;
  logic mmio_error;

  integer init_index;

  // FPGA bitstream loaders commonly support initialized inferred memories.
  // This is intentionally not an ASIC memory-reset strategy.
  initial begin
    for (init_index = 0; init_index < ROM_WORDS; init_index = init_index + 1) begin
      boot_rom[init_index] = 32'h0000_0013;  // RISC-V NOP
    end
    for (init_index = 0; init_index < SRAM_WORDS; init_index = init_index + 1) begin
      sram[init_index] = 32'h0000_0000;
    end
    if (ROM_INIT_FILE != "") begin
      $readmemh(ROM_INIT_FILE, boot_rom);
    end
  end

  assign rom_select = cpu_mem_valid && (cpu_mem_addr < BOOT_ROM_BYTES);
  assign sram_select = cpu_mem_valid &&
                       (cpu_mem_addr >= SRAM_BASE) &&
                       (cpu_mem_addr < SRAM_END);
  assign mmio_select = cpu_mem_valid &&
                       (cpu_mem_addr >= MMIO_BASE) &&
                       (cpu_mem_addr < MMIO_END);
  assign unmapped_select = cpu_mem_valid &&
                           !rom_select && !sram_select && !mmio_select;
  assign rom_word_index = cpu_mem_addr[ROM_ADDR_BITS+1:2];
  assign sram_word_index = cpu_mem_addr[SRAM_ADDR_BITS+1:2];

  // There is no architectural access-fault exception in the minimal v0
  // PicoRV32 adapter. This signal is a diagnostic for simulation and board
  // bring-up; the longer-term CPU/debug adapter will promote it to an error.
  assign bus_error_o = unmapped_select ||
                       (rom_select && (|cpu_mem_wstrb)) ||
                       (mmio_select && mmio_error);

  always_ff @(posedge clk_i) begin
    if (sram_select && (|cpu_mem_wstrb)) begin
      sram[sram_word_index] <= merge_write(
        sram[sram_word_index],
        cpu_mem_wdata,
        cpu_mem_wstrb
      );
    end
  end

  omcu_mmio_fabric #(
    .GPIO_COUNT(GPIO_COUNT),
    .ROM_BYTES(BOOT_ROM_BYTES),
    .SRAM_BYTES(SRAM_BYTES)
  ) mmio (
    .clk_i(clk_i),
    .rst_ni(rst_ni),
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
    .timer_irq_o(timer_irq_o)
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
    end else if (mmio_select) begin
      cpu_mem_ready = mmio_ready;
      cpu_mem_rdata = mmio_read_data;
    end else if (unmapped_select) begin
      // Acknowledge bad accesses so the core cannot deadlock during bring-up.
      cpu_mem_ready = 1'b1;
    end
  end

  picorv32 #(
    .ENABLE_COUNTERS(1'b1),
    .ENABLE_COUNTERS64(1'b1),
    .ENABLE_REGS_16_31(1'b1),
    .ENABLE_REGS_DUALPORT(1'b1),
    .LATCHED_MEM_RDATA(1'b0),
    .TWO_STAGE_SHIFT(1'b1),
    .BARREL_SHIFTER(1'b0),
    .TWO_CYCLE_COMPARE(1'b0),
    .TWO_CYCLE_ALU(1'b0),
    .COMPRESSED_ISA(1'b0),
    .CATCH_MISALIGN(1'b1),
    .CATCH_ILLINSN(1'b1),
    .ENABLE_PCPI(1'b0),
    .ENABLE_MUL(1'b0),
    .ENABLE_FAST_MUL(1'b0),
    .ENABLE_DIV(1'b0),
    .ENABLE_IRQ(1'b0),
    .ENABLE_TRACE(1'b0),
    .PROGADDR_RESET(32'h0000_0000),
    .PROGADDR_IRQ(32'h0000_0010),
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
    .pcpi_valid(),
    .pcpi_insn(),
    .pcpi_rs1(),
    .pcpi_rs2(),
    .pcpi_wr(1'b0),
    .pcpi_rd(32'h0000_0000),
    .pcpi_wait(1'b0),
    .pcpi_ready(1'b0),
    .irq(32'h0000_0000),
    .eoi(),
    .trace_valid(),
    .trace_data()
  );

endmodule

`default_nettype wire
