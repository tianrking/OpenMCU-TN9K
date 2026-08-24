# Tang Nano 9K platform backend

The first board target is now a deliberately small, inspectable hardware
bring-up configuration:

- `omcu_tn9k_bringup_top.sv` runs the portable SoC directly at the board's
  27 MHz input and synchronizes reset deassertion;
- `firmware/gpio_bringup.hex` is a five-instruction RISC-V image that enables
  GPIO0[0] and lights LED0;
- `project/omcu_tn9k_bringup.gprj` selects `GW1NR-LV9QN88PC6/I5`;
- `project/*.cst` and `project/*.sdc` record the bring-up pins, USB-UART pins
  and 27 MHz timing constraint.

The pin locations were independently cross-checked against Sipeed's public
`picotiny` project at revision
`c3b795799f23de91982be52db4273a8eea100cdb`; they have not yet been tested on
this physical board. No Sipeed RTL or generated IP was copied into OpenMCU.

## Build an open `.fs` artifact

First initialize the separately licensed CPU source:

```powershell
git submodule update --init --recursive
```

For a reproducible open build, install the version-pinned YoWASP/Yosys,
nextpnr-himbaechel-gowin and Apycula packages described in
[`../../../docs/open-pnr.md`](../../../docs/open-pnr.md), then run:

```powershell
$tools = 'C:\path\to\yowasp-gowin\Scripts'
.\scripts\build-tangnano9k-open.ps1 -ToolBin $tools
```

The result is `build/tangnano9k-open/omcu_tn9k_bringup.fs`, accompanied by its
P&R report and SHA-256 manifest. The build script checks that the project
contains all current portable RTL sources, uses the exact device/package and
meets the declared 27 MHz clock constraint.

To select a built SDK application instead of the default LED ROM fixture, add
`-RomInitFile .\build\sdk\omcu_uart_hello.hex` (or any other generated ROM
image inside the repository). The full command is documented in
[`../../../docs/open-pnr.md`](../../../docs/open-pnr.md).

`project/omcu_tn9k_bringup.gprj` remains useful for a separately installed
GOWIN EDA cross-check. Open it, synthesize/place/route it, then compare timing,
utilization and board behavior rather than treating the two flows as
interchangeable without evidence.

## Deliberate limits of this target

It uses direct 27 MHz clocking and inferred initialized memories solely to make
the first observable board test small. It has no PLL, flash loader, debugger,
header GPIO mapping, PSRAM or programming automation yet. SPI0,
I2C0 and PWM0 board pins are not silently assigned by this bring-up target;
their RTL and SDK support must be bound to a verified connector constraint set
before a board release. I2C0 has a generic open-drain byte engine, but no Tang
header assignment or physical pull-up verification yet.
UART0 RTL
and board pins are present, but the current ROM fixture only lights LED0;
`sdk/examples/uart_hello` needs a verified toolchain-to-ROM-image path before
it can be used on hardware. No board programming or board-level regression has
been performed for the generated `.fs`; those are later explicit release gates,
so this source must not be described as a supported third-party board release.
