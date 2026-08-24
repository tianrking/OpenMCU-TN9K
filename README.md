# OpenMCU-TN9K

`OpenMCU-TN9K` is the FPGA-prototype backend of an MCU project that is intended
to grow into a real ASIC-backed development platform. It is deliberately not a
one-off RISC-V demo: the hardware register contract, SDK, simulator, Tang Nano
9K build, and future ASIC wrapper are treated as one product.

## Project promise

The same bare-metal application must be able to run, with only a board target
change, in three environments:

```text
software simulation -> Tang Nano 9K FPGA -> OpenMCU-A0 ASIC board
```

The CPU implementation may change during early bring-up, but the following
contracts must not change silently:

- RISC-V toolchain ABI and startup convention;
- memory map and peripheral register definitions;
- interrupt and reset semantics;
- firmware-image and update format;
- public SDK API and generated device metadata.

## Status

This repository is at the executable MCU-prototype stage. It contains the v0
memory-map contract, portable GPIO/UART/timer/SPI/I2C/watchdog/PWM/SYSCTRL RTL,
a PicoRV32 RV32IMC CPU adapter, SDK headers/examples, real Tang Nano 9K pad
bindings, safe SRAM-first programming tooling, and the Tang/ASIC separation
rules. Directed end-to-end simulation executes compiled RISC-V firmware from
ROM through the real MMIO fabric and the actual Tang top-level ports.

The latest local open-source YoWASP result synthesized, placed, routed and
packed the exact `GW1NR-LV9QN88PC6/I5` target with the compiled
`omcu_peripheral_smoke` ROM, 8 KiB ROM and 44 KiB SRAM. It achieved
37.803 MHz against the 27 MHz constraint (10.584 ns calculated margin), used
6,167/8,640 LUT4s and all 26/26 BSRAMs, and emitted a manifest-bound `.fs`
with SHA-256 `9384549f0f380e26e3b23b2d7d00f3bcf127d556553670e263f30e6ff3f77c83`.
See [`docs/open-pnr.md`](docs/open-pnr.md) and the Chinese
[developer guide](docs/zh-CN/README.md).

That is a meaningful FPGA-build result, not a physical-board pass: no bitstream
has been programmed into a Tang board in the current workspace. The supplied
programming script validates the manifest/hash and defaults to volatile SRAM,
but it cannot substitute for board-level electrical and peripheral regression.
This project also does not claim vendor-flow equivalence or ASIC layout
validation.

The workstation has no globally installed Verilog simulator, RISC-V cross
compiler, Gowin EDA or openFPGALoader on `PATH`. Workspace-local Icarus Verilog,
a SHA-256-verified xPack GNU RISC-V toolchain, and pinned YoWASP/Yosys,
nextpnr-himbaechel and Apycula packages run the directed RTL, compiled-SDK and
open-P&R checks. See [`docs/validation.md`](docs/validation.md).

For portable RTL smoke tests, install Icarus Verilog or point the test runner
at an unpacked copy: `$env:OMCU_IVERILOG_BIN = 'C:\path\to\iverilog\bin'`.

## v0 scope

| Implemented in the current prototype | Reserved ABI / next implementation | Deliberately deferred |
| --- | --- | --- |
| RV32IMC adapter, 8 KiB ROM / 44 KiB SRAM Tang configuration | QSPI XIP and external-flash loader | Internal Flash / eFlash |
| GPIO0, UART0, TIMER0, SPI0, I2C0, WDT0, PWM0, SYSCTRL | Public interrupt ABI | ADC, DAC, analogue reference |
| Generated C register header, Tang board header, and SDK examples | JTAG/serial-debug | USB PHY, Ethernet PHY, radio |
| Tang 27 MHz / LED / UART / SPI / I2C / PWM / GPIO target, P&R and manifest-checked downloader | Physical-board release | Low-power sign-off, production packaging and ATE |

The first ASIC should boot from external QSPI flash. That keeps the A0 chip
fully real and useful without pretending that an open-flow test chip already
has qualified embedded Flash or analogue IP.

## Repository layout

```text
docs/                  Architecture, SDK and validation contracts
asic/                  Explicit FPGA-to-ASIC handoff and tapeout gates
rtl/bus/               Technology-neutral MMIO/bus definitions
rtl/cpu/               Replaceable CPU adapters and executable system wrappers
rtl/peripherals/       Technology-neutral peripheral RTL
rtl/platform/sim/      Simulation-specific wrappers
rtl/platform/tangnano9k/  Gowin-specific clock, RAM and pin wrappers
sdk/                   Public headers and bare-metal examples
tests/                 RTL, firmware and board-level test plan
third_party/           Pinned, separately licensed upstream dependencies
```

## Design principles

1. **No vendor primitive leaks into the SoC contract.** Gowin BRAM/PLL and
   ASIC SRAM/pad cells belong behind platform wrappers.
2. **A register is an API.** Every register has reset, width, access and
   side-effect semantics before an SDK function is written.
3. **FPGA success is not ASIC sign-off.** FPGA testing proves functionality;
   ASIC timing, DRC/LVS, power integrity, pad ring, DFT and packaging remain
   separate gates.
4. **A demo is not an SDK.** Public release requires versioned headers,
   linker scripts, boot/update tooling, documentation and regression tests.

## Starting references, not code to fork blindly

- [NEORV32](https://github.com/stnolting/neorv32): complete MCU-class soft SoC
  and software framework; useful architecture reference, but VHDL-based.
- [Ibex Demo System](https://github.com/lowRISC/ibex-demo-system): a useful
  SystemVerilog reference for debug, UART, GPIO, PWM, timer and SPI.
- [PicoSoC](https://github.com/YosysHQ/picorv32/tree/main/picosoc): useful
  minimal external-SPI-flash boot reference.
- [OpenROAD Flow Scripts](https://github.com/The-OpenROAD-Project/OpenROAD-flow-scripts): future RTL-to-GDS learning and ASIC-flow reference.

See [`docs/architecture.md`](docs/architecture.md) for the actual OpenMCU
contract and [`docs/evidence.md`](docs/evidence.md) for the Tang Nano 9K gap
assessment. The usable v0 peripheral details are in
[`docs/registers.md`](docs/registers.md).

## Current CPU implementation record

The first executable adapter uses the ratified unprivileged RV32IMC configuration of
[PicoRV32](https://github.com/YosysHQ/picorv32), pinned as a submodule at
`a473fc8fca393771d83b0ffcf0b14db3393339d8`. It is a bring-up choice rather
than a public peripheral dependency: the CPU only sees the OpenMCU memory map
and portable MMIO fabric. Its exact licence and provenance are in
[`LICENSES.md`](LICENSES.md).

## ARM CPU route: explicit authorization gate

The repository does **not** include an ARM/Cortex-M RTL core or claim an ARM
bitstream. Such IP has separate licensing and redistribution conditions; an
unlicensed placeholder would not be a usable ARM MCU. The public RISC-V design
is Apache-2.0 (except separately licensed dependencies), while the ARM route is
documented as an independent, authorization-dependent backend in
[`docs/zh-CN/arm-license-and-integration.md`](docs/zh-CN/arm-license-and-integration.md).
Once an owner supplies a valid core license and delivery approved for this
Gowin target, it can reuse the documented peripheral/pad contract without
placing proprietary core files in Git.

## Reproducibility scaffold

The repository contains a machine-readable register specification, a checked
generator for the C register header, a CMake RV32IMC firmware build wrapper,
an open Tang Nano P&R/packing script, a SHA-256/manifest-aware programming
script and a CI workflow that exercises the portable checks. These are
deliberately distinguished from release evidence: CI is not evidence until it
passes for the final pushed commit, and no board programming result exists yet.

The FPGA-to-chip boundary is documented in [`asic/README.md`](asic/README.md):
it defines a credible external-QSPI A0 rather than implying the Tang bitstream
is already an ASIC tapeout.
