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
`PATH`. A workspace-local Icarus Verilog 11.0 copy, a workspace-local xPack
GNU RISC-V Embedded GCC 15.2.0-1 package, and an isolated YoWASP environment
were used for these checks. The xPack Windows archive SHA-256 matched the pinned
value in
[`toolchains/riscv-none-elf-gcc-15.2.0-1.lock.json`](../toolchains/riscv-none-elf-gcc-15.2.0-1.lock.json);
the open FPGA package versions are recorded in
[`toolchains/yowasp-gowin.lock.json`](../toolchains/yowasp-gowin.lock.json).

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
- `omcu_tn9k_peripheral_io_tb`: passed; compiled SDK firmware reached the
  actual Tang top-level SPI0 chip-select, PWM0 and tri-state GPIO/I2C pad
  adapters. This is a digital top-level connectivity test, not an electrical
  connector test.
- `scripts/generate-sdk.ps1 -Check`: passed; generated C register definitions
  match `spec/omcu-v0.json`.

Icarus emitted informational limitations about `unique case` and constant
select sensitivity in `always_comb`; it did not report a compilation failure.

The following open source-to-bitstream checks also passed on the exact Tang
Nano 9K target:

- `scripts/check-tangnano9k-project.ps1`: passed; the GOWIN project covers all
  13 canonical RTL sources, the Tang wrapper, one CST and one SDC for
  `GW1NR-LV9QN88PC6/I5`.
- `scripts/build-tangnano9k-open.ps1 -RomInitFile
  .\build\sdk\omcu_tn9k_board_demo.hex -RomKiB 8 -SramKiB 44`: passed using
  Yosys 0.68, nextpnr-himbaechel-gowin 0.11.1 and Apycula 0.32.
- The same command with `omcu_peripheral_smoke.hex` instead of the board demo:
  passed with the same device, constraints, memory geometry and tool versions.
- For each build, the script converts the sparse input `.hex` into a dense
  2,048-word NOP-padded image, supplies it as the literal boot-ROM
  `$readmemh` input during front-end parsing, then hashes the `INIT_RAM_xx`
  data of the four boot-ROM BSRAM cells in both the synthesized and P&R JSON.
  A build fails if those two fingerprints differ.
- Board demo: input SHA-256
  `b35a525d571abe90fe034373e8108a4843544e78b59189cdeade8c3fab19bb30`,
  synthesized/P&R BSRAM fingerprint
  `291fd35b7018e0b5b45a3995793ed94b16811bf19569fec304d3238ec7172655`,
  packed bitstream SHA-256
  `615ac5b62e9a84ab538cb9d831aaef3d668fb43370b569b5f7adfc4590c97e3a`.
- Peripheral smoke: input SHA-256
  `dbaf313dc1b12980e954665b799ea53578a31b1a1ea0d05a34961581c7f6acd7`,
  synthesized/P&R BSRAM fingerprint
  `4b1ecd0e29b6ae5ebfe9548d76193cf1ea17207f64a290e57b23b1c4acc3e86f`,
  packed bitstream SHA-256
  `2f33fc5518a8fdedb1520aa185a115c68babf27421d7d6368fcb68b53f5f31e8`.
- The two input, BSRAM and bitstream hash sets differ. This establishes that
  compiled SDK firmware reaches the initialized BSRAM and final packed FPGA
  image; it is stronger than merely recording an intended input filename.
- Each final routed report found the single `system.clk_i` domain at 41.123 MHz
  against a 27.000 MHz constraint, a calculated 12.720 ns margin. Selected
  utilization was 5,722/8,640 LUT4s (66.23%), 1,606/6,480 DFFs (24.78%),
  26/26 BSRAMs (100%), 1,056/6,480 ALUs (16.30%), one of five MULT36X36s, and
  15/276 I/O buffers (including bidirectional-pad buffers).

Yosys emitted its known limited-tri-state warning for the I2C and GPIO top-level
pad adapters; the log is retained and this result is not described as a
warning-free sign-off. The script exited only after nextpnr reported normal
completion, after it compared BSRAM initialization, and after it verified the
timing threshold. An open P&R result is still not a physical-board test or a
vendor-flow equivalence claim.

These checks establish directed RTL behavior, compiler/simulator integration,
and a reproducible FPGA configuration image. Programmer integration and
physical-board behavior remain unvalidated: no `.fs` has been loaded on this
board, and reset, clock, LED polarity, UART electrical behavior and connector
I/O still require a real-board matrix.

The repository includes a GitHub Actions workflow that installs Icarus and a
GNU RISC-V toolchain, then runs the smoke suite and builds every current SDK
firmware target.
It is a planned reproducibility gate, not evidence of a CI run until the
repository is pushed and that workflow has completed for the exact commit.
