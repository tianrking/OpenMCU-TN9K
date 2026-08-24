# OpenMCU SDK bring-up build

This is the first compiler-facing SDK route for the current 4 KiB ROM / 32 KiB
SRAM Tang Nano 9K prototype configuration. It targets RV32I with the ILP32
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

The outputs include `omcu_blink.elf` / `.map` / `.hex` and
`omcu_uart_hello.elf` / `.map` / `.hex`. The final ROM image format must be
rechecked with the selected GNU toolchain before it is used to program a board:
no RISC-V toolchain is installed in this workspace, so this path has not yet
been compiled or flashed here.

`omcu_fpga_bringup.ld` is only for the current 4 KiB/32 KiB FPGA ROM/RAM
configuration. A public SDK release will select a target-specific memory file
from hardware metadata rather than asking applications to edit a linker script.
