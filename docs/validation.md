# Validation gates

## Required gates before a Tang Nano 9K release

1. RTL unit tests for every peripheral and register side effect.
2. SoC simulation: reset, trap, interrupt, GPIO, UART loopback, SPI and I2C
   transaction fixtures.
3. RISC-V firmware build with a pinned cross compiler.
4. Gowin synthesis and place-and-route with zero unconstrained clocks and
   documented timing report.
5. On-board tests: cold reset, 1,000 reset cycles, UART at documented baud,
   flash update interruption, GPIO loopback, timer/PWM measurement and I2C/SPI
   loopback.
6. A reproducible release artifact: bitstream hash, firmware hash, tool
   versions and board revision.

## Required gates before an ASIC claim

FPGA validation is necessary but insufficient. ASIC release additionally needs
the selected PDK flow, pad ring, ESD and power checks, SRAM macro integration,
DFT/scan plan, timing sign-off, DRC/LVS, package selection, wafer/packaged-die
bring-up and an ATE or production test strategy.

## Current workstation state

On 2026-08-25 this workspace exposes Git, CMake and Ninja, but not a Verilog
simulator, Yosys, Gowin EDA, openFPGALoader or a RISC-V cross compiler on
`PATH`. A temporary, workspace-local Icarus Verilog 11.0 copy was used for the
first portable RTL smoke tests:

- `omcu_timer_tb`: passed;
- `omcu_gpio_tb`: passed;
- `omcu_uart_tb`: passed; it verifies 8-N-1 TX, RX data recovery, status and
  RX interrupt behavior at a directed simulation divider;
- `omcu_mmio_fabric`: compiled successfully with all implemented portable
  peripherals.
- `omcu_sysctrl_tb`: passed; it verifies ABI, feature, build and memory
  metadata encoding.
- `omcu_picorv32_system_tb`: passed; it executed a five-instruction RV32I ROM
  image through PicoRV32 and observed GPIO0 output enable/high state.
- `omcu_picorv32_uart_system_tb`: passed; an RV32I image configured UART0
  through the real MMIO fabric and emitted a checked serial byte.
- `omcu_tn9k_bringup_top_tb`: passed; it added the 27 MHz reset release and
  active-low LED mapping around the same executable system.
- `scripts/generate-sdk.ps1 -Check`: passed; generated C register definitions
  match `spec/omcu-v0.json`.

Icarus emitted informational limitations about `unique case` and constant
select sensitivity in `always_comb`; it did not report a compilation failure.
Those checks establish only directed RTL behavior. Gowin synthesis,
place-and-route, RISC-V firmware compilation, programmer integration and a
physical-board test remain unvalidated.

The repository includes a GitHub Actions workflow that installs Icarus and a
GNU RISC-V toolchain, then runs the smoke suite and builds the blink example.
It is a planned reproducibility gate, not evidence of a CI run until the
repository is pushed and that workflow has completed for the exact commit.
