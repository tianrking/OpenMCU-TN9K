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

The v0.3 SDK now includes device/feature discovery, GPIO, timer, UART console,
polled SPI byte transfer, composable I2C START/STOP/read/write-byte helpers,
watchdog start/feed/stop and PWM configuration. I2C helpers return `false` for
disabled hardware, invalid command sequencing or a target NACK. They do not
silently invent a transaction timeout; applications choose that policy around
the calls. The SDK still needs a standards-complete trap/interrupt dispatch
layer, serial/QSPI programmer, board-information CLI and target metadata
loader.
The hardware feature bitmap is authoritative: an SDK helper must not assume an
optional peripheral merely because its base address is reserved.
