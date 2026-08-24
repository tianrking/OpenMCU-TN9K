# OpenMCU v0 register reference

All v0 MMIO registers are 32-bit little-endian and word-aligned. Addresses are
stable within ABI major version 0. The reviewed machine-readable register
source is [`spec/omcu-v0.json`](../spec/omcu-v0.json); the C register header is
generated from that source.

## GPIO0 — `0x4000_0000`

All GPIO bit fields apply to the implemented GPIO width; the current Tang
bring-up target uses the first six bits for active-low LEDs.

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `OUT` | RW | Output latch |
| `0x04` | `OUT_SET` | WO | Set output bits written as one |
| `0x08` | `OUT_CLR` | WO | Clear output bits written as one |
| `0x0C` | `OUT_XOR` | WO | Toggle output bits written as one |
| `0x10` | `OE` | RW | Output-enable latch |
| `0x14` | `OE_SET` | WO | Enable output bits written as one |
| `0x18` | `OE_CLR` | WO | Disable output bits written as one |
| `0x20` | `IN` | RO | Input sample; external asynchronous inputs need a platform synchronizer |
| `0x24` | `RISE_EN` | RW | Rising-edge interrupt enable bits |
| `0x28` | `FALL_EN` | RW | Falling-edge interrupt enable bits |
| `0x2C` | `IRQ_STATUS` | RW1C | Latched edge flags; write one to clear |

## UART0 — `0x4000_1000`

UART0 is 8-N-1. `BAUDDIV` is system-clock cycles per bit minus one; use `233`
for approximately 115200 baud with a 27 MHz system clock.

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `DATA` | RW | Bits `7:0`: TX byte on write; RX byte on read. Reading consumes `RX_VALID`. |
| `0x04` | `STATUS` | RW | Bit 0 `TX_READY`, bit 1 `RX_VALID`, bit 2 `RX_OVERRUN` (W1C), bit 3 `RX_FRAMING_ERROR` (W1C), bit 4 `TX_BUSY`. |
| `0x08` | `BAUDDIV` | RW | Bits `15:0`: cycles per bit minus one; reset `233`. |
| `0x0C` | `CTRL` | RW | Bit 0 `TX_ENABLE`, bit 1 `RX_ENABLE`, bit 2 `RX_IRQ_ENABLE`. |

`irq_o` is asserted while `RX_VALID` and `RX_IRQ_ENABLE` are both one. The
first v0 CPU adapter does not yet expose a public interrupt ABI, so firmware
should poll until that architecture is finalized.

## TIMER0 — `0x4000_2000`

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | RW | Bit 0 `ENABLE`, bit 1 `IRQ_ENABLE`, bit 2 `AUTO_RELOAD`. |
| `0x04` | `PRESCALE` | RW | Bits `15:0`: timer clocks per count minus one. |
| `0x08` | `COUNT` | RW | Current count. |
| `0x0C` | `COMPARE` | RW | Compare count. |
| `0x10` | `STATUS` | RW1C | Bit 0 `PENDING`; write one to clear. |

A non-reloading timer stops at its compare. An auto-reloading timer returns to
zero and continues.

## SYSCTRL — `0x4000_F000`

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `CHIP_ID` | RO | `0x4F4D4355` (`OMCU`) |
| `0x04` | `ABI` | RO | ABI major in bits `31:16`, minor in bits `15:0` |
| `0x08` | `FEATURES` | RO | Bit 0 GPIO0, bit 1 UART0, bit 2 TIMER0 |
| `0x0C` | `BUILD_ID` | RO | Platform build identifier |
| `0x10` | `MEMORY_KIB` | RO | SRAM KiB in bits `31:16`, ROM KiB in bits `15:0` |

Applications should check `CHIP_ID`, ABI major and required feature bits before
using optional hardware. `omcu_hw_abi_is_compatible()` provides the first C
helper for that check.
