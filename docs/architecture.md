# OpenMCU v0 architecture contract

## Product boundary

OpenMCU is a small, conventional, software-friendly RISC-V MCU. It is not an
FPGA demo protocol, a Linux-capable computer, or a custom ISA experiment.

The initial CPU adapter must implement a standards-conformant 32-bit RISC-V
bare-metal target. A compact PicoRV32-based adapter is acceptable for Tang
bring-up; an Ibex-based adapter is the leading candidate for the longer-term
SystemVerilog product route. Either choice is behind a CPU adapter and cannot
change the public peripheral ABI.

## Stable v0 memory map

| Address range | Block | Notes |
| --- | --- | --- |
| `0x0000_0000-0x0000_FFFF` | boot ROM aperture | Immutable reset vector and external-flash loader |
| `0x1000_0000-0x1000_FFFF` | main SRAM aperture | Platform wrapper selects FPGA BRAM or ASIC SRAM macro |
| `0x2000_0000-0x20FF_FFFF` | QSPI/XIP window | External firmware storage; exact size is board-dependent |
| `0x4000_0000-0x4000_0FFF` | GPIO0 | v0 portable GPIO peripheral |
| `0x4000_1000-0x4000_1FFF` | UART0 | Console, loader and diagnostics |
| `0x4000_2000-0x4000_2FFF` | TIMER0 | v0 portable timer peripheral |
| `0x4000_3000-0x4000_3FFF` | SPI0 | External devices / QSPI control boundary |
| `0x4000_4000-0x4000_4FFF` | I2C0 | Standard sensor bus |
| `0x4000_5000-0x4000_5FFF` | WDT0 | Independent watchdog |
| `0x4000_F000-0x4000_FFFF` | SYSCTRL | Chip ID, build ID, reset reason and clock metadata |

No compatible release may move an existing block. New functions receive a new
range; an incompatible behavior requires a new major device revision.

The listed ROM and SRAM regions are reserved address apertures, not a promise
that every early prototype implements 64 KiB of each. The current executable
adapter defaults to 4 KiB of boot ROM and 32 KiB of SRAM, which is a realistic
first BRAM budget for Tang Nano 9K bring-up. A later `SYSCTRL` implementation
must expose the exact usable capacities and feature bitmap before third-party
firmware can rely on them.

## Portable MMIO transaction

The first internal bus is intentionally small. CPU adapters translate their
native bus to these signals:

```text
req, write, address[31:0], write_data[31:0], write_strobe[3:0]
                                -> ready, read_data[31:0], error
```

This avoids exposing PicoRV32, Ibex, LiteX, Wishbone, APB, Gowin or ASIC
implementation details to peripherals. The v0 peripheral bus is single-master,
single-cycle-ready for simple blocks; a future interconnect may pipeline the
transaction but must preserve visible ordering and register semantics.

## v0 executable CPU adapter

`rtl/cpu/omcu_picorv32_system.sv` turns the portable blocks into an executable
RV32IMC system. It keeps PicoRV32 behind the memory-map adapter and connects:

```text
PicoRV32 -> ROM / SRAM / OpenMCU MMIO fabric -> GPIO0 + TIMER0
```

The adapter enables the ratified `M` and `C` instruction extensions and a
barrel shifter, but intentionally does **not** claim `Zicsr`, privileged machine
mode, debug support, atomics, floating point, or PicoRV32's non-standard
interrupt facility. GPIO and timer IRQ signals are exposed for validation, but
no third-party interrupt ABI is claimed until the CPU/debug architecture and
startup code are specified. Invalid or ROM-write transactions are acknowledged
and surfaced as a simulation/bring-up diagnostic; the minimal adapter does not
yet turn them into a RISC-V access fault.

The ROM initialization file is a simulation/FPGA-bring-up mechanism, not the
final update solution. The product boot path remains: immutable loader ->
verified external-QSPI firmware -> SRAM execution.

## Reset and clock contract

- `clk_i` is the synchronous system clock after a platform-specific PLL/clock
  wrapper. No generic RTL may instantiate a Gowin PLL.
- `rst_ni` is an active-low reset that is asserted asynchronously by the
  platform and released synchronously only after clock lock is valid.
- All public peripheral registers reset to documented values.
- ASIC A0 uses an external clock input and external reset supervisor. Internal
  RC oscillators, brown-out detector and low-power clocks are later revisions.

## Hardware/software version handshake

The implemented v0 `SYSCTRL` block exposes the `OMCU` chip identifier, ABI
major/minor, feature bitmap, build identifier and actual ROM/SRAM KiB. Firmware
must reject a device whose major ABI version is unsupported instead of
accidentally writing incompatible registers. Reset reason and a full build
digest remain later additions. See [`registers.md`](registers.md).

## Platform split

```text
             common RTL and register specification
   +---------------------------------------------------+
   | CPU adapter -> MMIO fabric -> portable peripherals |
   +---------------------------------------------------+
          |                    |                 |
       sim wrapper       Tang Nano wrapper     ASIC wrapper
          |                    |                 |
      RAM model        Gowin RAM/PLL/I/O    SRAM/pads/DFT/clock
```

The FPGA board is a hardware model of the ASIC function, not a claim that its
clock, SRAM, flash, I/O timing, power or reset circuits equal the final chip.
[`asic/README.md`](../asic/README.md) is the required handoff gate before an
MPW/foundry implementation begins.
