# OpenMCU-TN9K RISC-V v1 profile

## Frozen compiler target

The Tang Nano 9K v1 hardware and SDK target **`rv32imc` with the `ilp32` ABI**.
That is a deliberately small MCU-class profile of the current ratified
unprivileged RISC-V ISA, not a claim to implement every RISC-V extension.

| Component | OpenMCU-TN9K v1 promise |
| --- | --- |
| Base integer ISA | RV32I, 32 general-purpose 32-bit registers |
| Multiply/divide | `M`, implemented with PicoRV32 fast multiply and divide PCPI units |
| Code density | `C`, enabled in the instruction fetch/decode path |
| Compiler ABI | `ilp32`, little-endian, freestanding bare metal |
| Synchronization | `FENCE` is accepted by the CPU adapter; the v1 bus has one master and ordered MMIO |
| Build string | `-march=rv32imc -mabi=ilp32` |

`RV32IMC` is canonical RISC-V ISA naming. The implementation source is the
pinned PicoRV32 revision recorded in `LICENSES.md`; its own documentation
states that it can be configured as an RV32IMC core.

## Explicit exclusions

Third-party code must not assume any of the following in v1:

- `A`, `F`, `D`, `Q`, `B`, vector, hypervisor, supervisor, or user-mode ISA;
- generic `Zicsr` CSR reads/writes, machine-mode trap CSRs, PMP, or standard
  RISC-V debug transport;
- a standard RISC-V interrupt controller or PicoRV32 custom IRQ opcodes;
- misaligned memory accesses, cache coherency, DMA, or Linux support.

The CPU can read its internal cycle/instruction counters through PicoRV32's
supported counter encodings, but this is not advertised as the full `Zicsr`
extension. A later standards-complete trap/interrupt core adapter is a new
hardware capability and must change the SYSCTRL feature bitmap and SDK support
at the same time.

## Why this is the 9K default

The 9K FPGA should be used for a product-quality microcontroller envelope:
full 32-register ABI, compact code, hardware multiply/divide and a barrel
shifter. Floating point, atomics and vectors would spend scarce LUT/BRAM on
capabilities that common GPIO, sensor, display and control firmware does not
need. The build and place-and-route report, rather than a prose estimate, is
the authority for the final resource/timing envelope.
