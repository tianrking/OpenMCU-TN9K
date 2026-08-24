# SDK contract

## Audience promise

An application developer should not need to know whether a program is running
in a simulator, the Tang Nano 9K FPGA image, or a packaged OpenMCU ASIC. The
SDK selects a board/chip target; the source-level peripheral API remains the
same within an ABI major version.

## Source of truth

The v0 machine-readable source is [`spec/omcu-v0.json`](../spec/omcu-v0.json).
`scripts/generate-sdk.ps1` turns it into the checked-in
[`sdk/include/omcu_regs.h`](../sdk/include/omcu_regs.h); `omcu.h` is the small
hand-written convenience layer built on those generated definitions. The
generator's `-Check` mode is a required CI gate once CI is enabled.

The corresponding human register reference is
[`docs/registers.md`](registers.md); it is reviewed alongside the JSON and RTL
until documentation generation is added.

The next step is to generate the register reference and Rust bindings from the
same reviewed source. Hand-editing generated register definitions is prohibited
because it creates silent hardware/software divergence.

## Versioning

- Hardware uses `major.minor.patch` semantic versioning in SYSCTRL metadata.
- A major version changes only for incompatible register behavior.
- New optional blocks are advertised by a feature bitmap.
- SDK releases pin cross-toolchain versions and record the supported hardware
  ABI range.

## Required public SDK functions

v0 must eventually include device startup, traps/interrupt dispatch, GPIO,
timer, UART console, SPI, I2C, watchdog, a serial/QSPI programmer and a board
information tool. The current `omcu.h` is only the beginning of that contract.
