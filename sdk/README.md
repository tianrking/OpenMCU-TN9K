# OpenMCU RV32IMC SDK

This SDK builds freestanding `rv32imc` / `ilp32` firmware for the OpenMCU Tang
Nano 9K target. The current public Tang linker layout is 8 KiB initialized ROM
and 44 KiB SRAM; it matches the all-BSRAM FPGA top-level configuration. It
emits an ELF, a map and a 32-bit-word Verilog `.hex` ROM image for each example.

The source-level register API is portable OpenMCU v0.4. `omcu_tn9k.h` is the
small board-support header: it provides the 27 MHz clock constant and logical
LED / expansion GPIO masks, not raw FPGA package pin numbers.

## Prerequisites

- CMake 3.20 or later and Ninja;
- a GNU bare-metal RISC-V toolchain with matching `gcc` and `objcopy`;
- the PicoRV32 submodule initialized at its recorded revision.

The recommended xPack naming uses `riscv-none-elf-gcc` and
`riscv-none-elf-objcopy`. Install a pinned xPack package with
`@xpack-dev-tools/riscv-none-elf-gcc@15.2.0-1.1` (or provide an equivalent
GNU bare-metal toolchain), put its `bin` directory on `PATH`, then run the
checked build wrapper from the repository root.

### Windows

```powershell
git submodule update --init --recursive
$env:PATH = 'C:\toolchains\riscv-none-elf\bin;' + $env:PATH
.\scripts\build-sdk.ps1 -RiscvPrefix riscv-none-elf-
```

If CMake or Ninja is not on `PATH`, pass their absolute paths with `-Cmake` and
`-Ninja`. The wrapper checks both compiler executables before configuring, so a
wrong prefix fails before a partial firmware build is mistaken for a result.
With CMake 3.24 or later, add `-Fresh` to discard generated CMake metadata in
the explicitly selected SDK build directory before reconfiguring.

### Linux and macOS

```sh
git submodule update --init --recursive
export PATH="/opt/xpack-riscv-none-elf/bin:$PATH"
sh ./scripts/build-sdk.sh --riscv-prefix riscv-none-elf-
```

`build-sdk.sh` accepts `--build-dir`, `--cmake`, `--ninja` and `--fresh`, with
the same intent as the PowerShell wrapper. It also honours
`OMCU_SDK_BUILD_DIR`, `OMCU_RISCV_PREFIX`, `OMCU_CMAKE` and `OMCU_NINJA`.
Both wrappers drive the same `sdk/cmake/riscv32-gcc.cmake` toolchain file, so
the host operating system does not change the generated RV32IMC firmware ABI.

For a portable xPack bootstrap, install `xpm` from npm, initialize a temporary
tooling directory, and install the pinned package there; xpm stores the binary
in its platform-specific store and creates a local link. Do not add the
temporary `package.json`, xPack cache, or generated build directory to a
firmware commit.

## Examples

| Target | Purpose |
| --- | --- |
| `omcu_blink` | Logical LED blink. |
| `omcu_uart_hello` | UART0 startup text. |
| `omcu_isa_smoke` | RV32IMC compiler/CPU integration test. |
| `omcu_peripheral_smoke` | GPIO, SPI0, PWM0 and WDT0 integration smoke test. |
| `omcu_i2c_smoke` | I2C START/write/read/STOP target-fixture test. |
| `omcu_irq_smoke` | TIMER0 -> IRQCTRL -> vector -> C hook -> `RETIRQ` integration test. |
| `omcu_wdt_reset_smoke` | Intentional WDT reset through the Tang wrapper. |
| `omcu_tn9k_board_demo` | UART, PWM, logical LED, three expansion GPIOs and WDT for a physical-board bring-up. |

The public interrupt contract is intentionally PicoRV32-specific rather than a
privileged RISC-V PLIC/CSR API. Applications define
`omcu_irq_dispatch(uint32_t pending)` and use the `omcu_irqctrl_*` helpers;
read [`docs/interrupts.md`](../docs/interrupts.md) before enabling a source.

Use a generated `.hex` as the ROM input to the separate FPGA build; never edit
an RTL ROM by hand:

```powershell
$tools = 'C:\toolchains\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools `
  -RomInitFile .\build\sdk\omcu_tn9k_board_demo.hex
```

This creates a manifest-bound `.fs` bitstream; it does not program a board.
Use `scripts/program-tangnano9k.ps1` for a manifest/hash-checked SRAM-first
download after reading the Chinese [build and programming guide](../docs/zh-CN/build-and-program.md).

## Memory-geometry rule

`omcu_fpga_bringup.ld` belongs to the default 8 KiB ROM / 44 KiB RAM Tang
configuration. If an experiment changes `-RomKiB` or `-SramKiB` in the FPGA
build, create and select a matching linker script before building firmware.
Using this linker file with a smaller hardware image can make an apparently
successful build fail unpredictably at runtime.
