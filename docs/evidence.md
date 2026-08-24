# Why OpenMCU-TN9K is a distinct project

The Tang Nano 9K already has useful RISC-V work, but the currently visible
projects solve different slices of the problem:

| Existing work | What it proves | What OpenMCU must add |
| --- | --- | --- |
| Sipeed `picotiny` example | PicoRV32, flash XIP, UART ISP and display integration work | Stable ABI, SDK, test matrix, documented product boundary |
| Sipeed NEORV32 example | User Flash program storage, GPIO, JTAG and UART upload work | Portable SoC contract and third-party release workflow |
| Community PicoRV32 projects | Small bare-metal software and individual peripherals work | Versioned API, debug/flash tools, regression and board support policy |
| Community Ibex + LiteX project | Open-flow Ibex + UART + memory + Wishbone can boot | Robust timing/RAM/baud validation and a supported release configuration |
| Tang-specific application projects | Complex individual application pipelines can run | A reusable MCU rather than an application-specific co-processor |

Sources checked on 2026-08-24:

- https://github.com/sipeed/TangNano-9K-example
- https://wiki.sipeed.com/hardware/en/tang/Tang-Nano-9K/examples/neorv32.html
- https://github.com/grughuhler/picorv32_tang_nano_unified
- https://github.com/riscv-ottawa/ibex-tang-nano-oss-cad
- https://github.com/LoveLonelyTime/LLTRISC-V
- https://github.com/calint/tang-nano-9k--riscv--cache-psram

This is a landscape observation, not a claim that no other implementation
exists. The differentiation is the full public product contract: simulation,
Tang backend, SDK, documentation, reproducible test gates, and an ASIC branch
in one maintained project.

## Board-binding provenance

For the OpenMCU Tang Nano 9K target, the 27 MHz clock, reset, LEDs, UART and
the extension-pad starting constraints were independently cross-checked against
the public Sipeed `picotiny` project and public board material; the original
LED source cross-check used revision
`c3b795799f23de91982be52db4273a8eea100cdb` (cloned for inspection only from
the first source above). The OpenMCU top-level RTL and constraints were written
independently; no upstream RTL, IP core or generated project file was copied.

This establishes traceability for a starting constraint set, not physical-board
validation. A Tang Nano 9K test must still verify the actual board revision,
USB power-up, reset polarity, LED polarity, clock stability, I/O bank voltage,
SPI/TF-card conflict, I2C pull-ups and timing report. The concrete constraints
and safety checklist are in [`zh-CN/hardware-and-pins.md`](zh-CN/hardware-and-pins.md).
