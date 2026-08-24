# OpenMCU v0.4 interrupt contract

OpenMCU v0.4 adds a complete, executable external-interrupt path for the
RV32IMC FPGA target. It covers peripheral event capture, software enable and
acknowledge registers, CPU delivery, a fixed vector, a full C-ABI save/restore
wrapper, and an SDK dispatch hook. The contract applies to the simulation and
Tang Nano 9K wrappers that advertise `OMCU_FEATURE_IRQCTRL`.

## Scope and compatibility boundary

This is a documented **PicoRV32 custom-IRQ ABI**, not the RISC-V privileged
architecture. In particular, it does not provide `mtvec`, `mstatus`, `mie`,
`mip`, a PLIC, CLINT, standard debug transport, or nested machine interrupts.
Portable OpenMCU applications must use the C functions in `omcu.h`; they must
not emit PicoRV32 custom opcodes or rely on q-register contents.

The register map and source-to-bit mapping are part of ABI major version 0.
New source types may be appended only with a new ABI minor and feature bit.

## Hardware path and source map

```text
GPIO / UART / TIMER / SPI / I2C / WDT event
                    |
                    v
          IRQCTRL: sticky pending + enable + force
                    |
                    v
          PicoRV32 external inputs 8 through 13
                    |
                    v
    fixed vector 0x10 -> SDK wrapper -> omcu_irq_dispatch(mask)
                    |
                    v
                  RETIRQ
```

| CPU bit / SDK constant | Source | Peripheral condition to service first |
| --- | --- | --- |
| 8 / `OMCU_IRQ_GPIO0` | GPIO0 | Read/handle the edge, then W1C `IRQ_STATUS`. |
| 9 / `OMCU_IRQ_UART0` | UART0 | Consume `DATA` while `RX_VALID` is asserted. |
| 10 / `OMCU_IRQ_TIMER0` | TIMER0 | Stop/rearm as appropriate, then W1C `STATUS.PENDING`. |
| 11 / `OMCU_IRQ_SPI0` | SPI0 | Read result if needed, then W1C `STATUS.DONE`. |
| 12 / `OMCU_IRQ_I2C0` | I2C0 | Finish the byte operation, then W1C terminal status bits. |
| 13 / `OMCU_IRQ_WDT0` | WDT0 | Apply the product policy, then clear expiry or stop/feed the watchdog. |

Bits 0 through 2 are reserved by PicoRV32 for its timer, illegal-instruction
and bus-error paths. Bits 3 through 7 and 14 through 31 are permanently
masked in this platform profile. `OMCU_IRQ_EXTERNAL_MASK` is exactly
`0x0000_3F00`.

## IRQCTRL registers

IRQCTRL is at `0x4000_7000`; its detailed fields are in
[`registers.md`](registers.md).

| Offset | Register | Meaning |
| --- | --- | --- |
| `0x00` | `PENDING` | RO sticky/current source bits in the CPU-bit positions. |
| `0x04` | `ENABLE` | RW source enable mask in the same bit positions. |
| `0x08` | `CLEAR` | WO W1C sticky and software-forced bits. A live source wins a coincident clear. |
| `0x0C` | `FORCE` | WO W1S software interrupt source; useful for diagnostics. |
| `0x10` | `ACTIVE` | RO `PENDING & ENABLE`, which is sent to the CPU. |
| `0x14` | `HIGHEST` | RO lowest numbered active CPU bit, or zero when none is active. |

`PENDING` captures short peripheral pulses even while disabled. `ENABLE` only
controls delivery, not capture. `FORCE` uses the same public bit masks as
hardware sources and is cleared through `CLEAR`.

## SDK initialization and handler contract

Enable an interrupt only after clearing stale peripheral and controller state:

```c
#include "omcu.h"

void omcu_irq_dispatch(uint32_t pending) {
  if ((pending & OMCU_IRQ_TIMER0) != 0u) {
    OMCU_TIMER0->ctrl = 0u;                         /* quiesce/rearm policy */
    OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING; /* clear at the source */
    omcu_irqctrl_ack(OMCU_IRQ_TIMER0);              /* then clear controller */
  }
}

static void enable_timer_irq(void) {
  omcu_irqctrl_set_enable(0u);
  omcu_irqctrl_ack(OMCU_IRQ_EXTERNAL_MASK);
  omcu_timer_start_periodic(0u, 27000u);
  omcu_irqctrl_set_enable(OMCU_IRQ_TIMER0);
  (void)omcu_irq_global_enable();
}
```

`omcu_irq_dispatch()` is a weak SDK function. An application supplies one
strong definition, which receives every simultaneously active CPU bit in
`pending`. It must service all bits it enables, or disable and acknowledge an
unhandled source before returning. The safe acknowledgement order is always:

1. Consume, clear, disable, or rearm the originating peripheral condition.
2. Write the matching bit to `IRQCTRL.CLEAR` through `omcu_irqctrl_ack()`.
3. Return from the C hook; the wrapper restores the interrupted application.

Clearing IRQCTRL first while a level-style source remains asserted creates a
new sticky event by design. This is not a lost-interrupt bug; it makes the
required peripheral-first ordering explicit.

`omcu_irq_global_enable()`, `omcu_irq_global_disable()` and
`omcu_irq_restore()` manipulate the CPU's documented custom IRQ mask. The
enable/disable calls return the previous mask, so a critical section should
save it and restore it rather than assuming the prior global state.

## Vector and execution rules

Reset begins at `0x0000_0000`; the linker reserves `0x00` through `0x0F` for
four uncompressed reset-vector words. PicoRV32 enters an external interrupt at
`0x0000_0010`, where the SDK wrapper:

1. protects the interrupted `ra`/`sp` using PicoRV32's documented q2/q3
   scratch registers;
2. saves x1 through x31 into a dedicated 128-byte frame;
3. switches to a dedicated 512-byte IRQ stack;
4. receives PicoRV32 q1 as the `pending` argument and calls the C hook;
5. restores the complete integer-register context and executes `RETIRQ`.

PicoRV32 blocks a second entry while an interrupt is active. Keep handlers
short, avoid blocking bus loops, and defer heavy work to the main loop. The
wrapper owns q0 through q3 and the custom opcodes; applications use only the
public C API.

## Executable regression

`omcu_irq_smoke` compiles from C, programs TIMER0, enables IRQCTRL bit 10 and
uses a strong C hook. `omcu_irq_sdk_tb` executes that exact ROM in the real
PicoRV32/MMIO RTL and requires the handler to run, `RETIRQ` to return to main,
and no trap or invalid MMIO transaction to occur. `omcu_irq_ctrl_tb` separately
checks latching, masking, priority, software force and clear semantics.

These are digital simulation proofs. Physical Tang Nano 9K download and
electrical peripheral validation remain separate release gates.
