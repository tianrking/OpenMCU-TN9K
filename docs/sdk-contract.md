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

The v0.4 SDK includes device/feature discovery, GPIO, timer, UART console,
polled SPI byte transfer, composable I2C START/STOP/read/write-byte helpers,
watchdog start/feed/stop, PWM configuration, and the executable external IRQ
entry points `omcu_irq_set_mask()`, `omcu_irq_wait()`,
`omcu_irq_global_enable()` and the IRQCTRL helpers. Applications install a
strong `omcu_irq_dispatch(uint32_t pending)` definition; the SDK's vector
wrapper owns the PicoRV32 custom instructions and full integer-register
preservation. The precise non-standard boundary and acknowledgement order are
part of [`interrupts.md`](interrupts.md).

`omcu_tn9k.h` adds the public 27 MHz board definitions and logical
LED/expansion-GPIO masks without leaking FPGA package numbers into applications.
I2C helpers return `false` for disabled hardware, invalid command sequencing or
a target NACK. They do not silently invent a transaction timeout; applications
choose that policy around the calls. The hardware feature bitmap is
authoritative: an SDK helper must not assume an optional peripheral merely
because its base address is reserved.

The checked build entry points are `scripts/build-sdk.ps1` on Windows and
`scripts/build-sdk.sh` on Linux/macOS. Both take an explicit GNU toolchain
prefix and drive the same CMake toolchain file, linker script and generated
register header. The supported-host CI matrix compiles every SDK target on
Windows, Linux and macOS; its result is still distinct from a board test.

The SDK still needs a serial/QSPI programmer, board-information CLI and target
metadata loader. A standards-complete privileged RISC-V trap/interrupt core is
also a future CPU-adapter feature, not an implied property of this ABI.
