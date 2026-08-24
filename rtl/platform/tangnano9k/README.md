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

## How to use the initial Gowin project

First initialize the separately licensed CPU source:

```powershell
git submodule update --init --recursive
```

Open `project/omcu_tn9k_bringup.gprj` in a GOWIN EDA installation, synthesize
and place-and-route it, then inspect the resulting timing and utilization
reports before programming a board. GOWIN documents `gw_sh.exe` as the
command-line entrypoint, but this repository intentionally does not yet call a
Gowin command automatically: the exact installed tool version, licence,
generated report paths and programmer are not available in this workspace to
validate an end-to-end command.

## Deliberate limits of this target

It uses direct 27 MHz clocking and inferred initialized memories solely to make
the first observable board test small. It has no PLL, flash loader, debugger,
header GPIO mapping, PSRAM or bitstream/programming automation yet. SPI0 and
PWM0 board pins are not silently assigned by this bring-up target; their RTL
and SDK support must be bound to a verified connector constraint set before a
board release. I2C0 remains a reserved address until its byte engine lands.
UART0 RTL
and board pins are present, but the current ROM fixture only lights LED0;
`sdk/examples/uart_hello` needs a verified toolchain-to-ROM-image path before
it can be used on hardware. Those are later explicit release gates, so this
source must not be described as a supported third-party board release.
