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
`PATH`. A workspace-local Icarus Verilog 11.0 copy and a workspace-local xPack
GNU RISC-V Embedded GCC 15.2.0-1 package were used for these checks. The xPack
Windows archive SHA-256 matched the pinned value in
[`toolchains/riscv-none-elf-gcc-15.2.0-1.lock.json`](../toolchains/riscv-none-elf-gcc-15.2.0-1.lock.json).

The following directed RTL smoke tests passed:

- `omcu_timer_tb`: passed;
- `omcu_gpio_tb`: passed;
- `omcu_uart_tb`: passed; it verifies 8-N-1 TX, RX data recovery, status and
  RX interrupt behavior at a directed simulation divider;
- `omcu_spi_tb`: passed; it verifies an 8-bit mode-0 transfer, MISO sampling,
  automatic chip select, DONE IRQ and W1C completion status.
- `omcu_i2c_tb`: passed; it verifies open-drain START/STOP/repeated-START
  sequencing, MSB-first write/read data, ACK/NACK status, command-sequence
  errors, `BUS_ACTIVE`, DONE IRQ and target clock-stretch waiting.
- `omcu_wdt_tb`: passed; it verifies feed, expiry, IRQ, reset request and W1C
  expiry status behavior.
- `omcu_pwm_tb`: passed; it verifies duty-cycle window, period rollover and
  inversion behavior.
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
- `omcu_rv32imc_sdk_tb`: passed; xPack GCC built the SDK with
  `-march=rv32imc -mabi=ilp32`, GNU `objcopy` generated the ROM image, and the
  image executed through the real PicoRV32, startup `.data` copy, MMIO fabric
  and GPIO peripheral. Its disassembly contains compressed instructions plus
  `mul`, `div`, `divu`, `rem`, and `remu` operations.
- `omcu_peripheral_sdk_tb`: passed; compiled C SDK calls discovered required
  features, configured PWM0/WDT0, executed a real SPI0 byte transfer and
  reported success through GPIO without a watchdog reset request.
- `omcu_i2c_sdk_tb`: passed; compiled C SDK calls issued the address/write/read
  byte sequence through the real PicoRV32/MMIO/I2C path against an open-drain
  target fixture, sampled the target response and sent its final-byte NACK.
- `omcu_tn9k_wdt_reset_tb`: passed; compiled C firmware intentionally expired
  WDT0 and the Tang reset-release wrapper reset and restarted the SoC.
- `scripts/generate-sdk.ps1 -Check`: passed; generated C register definitions
  match `spec/omcu-v0.json`.

Icarus emitted informational limitations about `unique case` and constant
select sensitivity in `always_comb`; it did not report a compilation failure.
Those checks establish only directed RTL behavior and local compiler/simulator
integration. Gowin synthesis, place-and-route, programmer integration and a
physical-board test remain unvalidated.

The repository includes a GitHub Actions workflow that installs Icarus and a
GNU RISC-V toolchain, then runs the smoke suite and builds every current SDK
firmware target.
It is a planned reproducibility gate, not evidence of a CI run until the
repository is pushed and that workflow has completed for the exact commit.
