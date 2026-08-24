# OpenMCU ASIC transition plan

This directory is deliberately a tapeout handoff boundary, not evidence that
OpenMCU has an ASIC layout or a manufacturable chip. The Tang Nano 9K is the
functional prototype target; an ASIC implementation starts only after the
following contracts are stable and exercised on FPGA.

## A0 product definition

The first physical OpenMCU should be a small, conventional external-QSPI-boot
MCU rather than an overambitious SoC:

- RV32I CPU adapter behind the existing OpenMCU memory/MMIO contract;
- SRAM macro(s), immutable boot ROM and external QSPI firmware storage;
- GPIO, UART, timer, SPI/QSPI control, watchdog and a debug/test interface;
- no assumed eFlash, ADC, DAC, USB PHY, radio, PLL, brown-out or analogue IP;
- an explicit pad-ring, ESD, power, reset, DFT/scan and package plan.

Keeping persistent firmware in external QSPI is intentional. It makes an A0
chip useful without pretending an educational/open PDK route includes qualified
embedded Flash or analogue macros.

## What transfers unchanged

The following are ASIC-neutral assets and should remain a single source of
truth:

```text
spec/omcu-v0.json -> generated SDK register definitions
rtl/bus/           -> memory-map and transaction behavior
rtl/peripherals/   -> GPIO / UART / timer / SYSCTRL functionality
sdk/               -> ABI-aware bare-metal applications
tests/             -> directed RTL and firmware integration regressions
```

The current `omcu_picorv32_system` memory arrays and Tang top-level do **not**
transfer unchanged. An ASIC integration must replace them with characterized
ROM/SRAM macro wrappers, pad cells, clocks/resets, DFT and technology-specific
constraints.

## Required gates before selecting an MPW or foundry

1. Freeze a versioned register reference, startup ABI, exception/interrupt
   policy and external firmware image/update format.
2. Validate the selected Tang Nano 9K configuration: synthesis, timing,
   bitstream hash, cold reset, UART, flash-update interruption and pin tests.
3. Select a foundry PDK, standard-cell library, SRAM compiler/macros, I/O pad
   library, package and test strategy with licences that allow the intended
   product and distribution model.
4. Build an ASIC wrapper with clock/reset, scan/DFT, pad ring, power domains,
   ESD and formal equivalence or focused RTL-vs-gate verification.
5. Complete synthesis, STA across sign-off corners, DRC/LVS, IR/EM, antenna,
   ERC, density/fill and manufacturability checks in the selected flow.
6. Plan wafer/packaged-die bring-up, programming, board support, production
   test vectors and ATE coverage before tapeout—not after first silicon.

## Three honest stages

| Stage | Purpose | Evidence required |
| --- | --- | --- |
| FPGA developer preview | Stabilize ABI and prove digital behavior on Tang Nano 9K | Passing RTL/firmware/board matrix and reproducible bitstream |
| A0 MPW learning silicon | Validate pad, reset, boot, I/O and manufacturing assumptions | Foundry sign-off reports plus packaged-die/board bring-up |
| Production MCU | Deliver a third-party-supported chip and development board | Qualified process/IP, production test, lifecycle/security/update policy |

Open-source PDK flows are valuable learning and pre-silicon verification tools,
but they do not by themselves establish a production-capable MCU supply chain.
The project must name its exact PDK and contractual manufacturing path before
claiming anything stronger than an experimental test chip.
