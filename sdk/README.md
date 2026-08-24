# OpenMCU SDK bring-up build

This is the first compiler-facing SDK route for the current 4 KiB ROM / 32 KiB
SRAM Tang Nano 9K prototype configuration. It targets RV32IMC with the ILP32
ABI, links a minimal startup routine, emits an ELF and asks GNU `objcopy` for a
32-bit Verilog ROM image.

## Prerequisites

- CMake 3.20 or later and Ninja (or another CMake generator);
- a GNU bare-metal RISC-V toolchain with a matching `gcc` and `objcopy`, for
  example `riscv32-unknown-elf-gcc` / `riscv32-unknown-elf-objcopy`;
- the PicoRV32 submodule initialized at its recorded revision.

## Build the blink example

From the repository root:

```powershell
cmake -S sdk -B build/sdk -G Ninja `
  -DCMAKE_TOOLCHAIN_FILE=sdk/cmake/riscv32-gcc.cmake `
  -DOMCU_RISCV_PREFIX=riscv32-unknown-elf-
cmake --build build/sdk
```

The outputs include `omcu_blink.elf` / `.map` / `.hex`,
`omcu_uart_hello.elf` / `.map` / `.hex`, and the compiled
`omcu_isa_smoke.elf` / `.map` / `.hex` and
`omcu_peripheral_smoke.elf` / `.map` / `.hex` and
`omcu_wdt_reset_smoke.elf` / `.map` / `.hex` integration tests. The final ROM
image format must be rechecked with the selected GNU toolchain before it is
used to program a board: the checked configuration is
`-DOMCU_MARCH=rv32imc -DOMCU_MABI=ilp32`. The SDK firmware build is
simulator-validated; it is not yet a flashed-board claim.

`omcu_fpga_bringup.ld` is only for the current 4 KiB/32 KiB FPGA ROM/RAM
configuration. A public SDK release will select a target-specific memory file
from hardware metadata rather than asking applications to edit a linker script.
