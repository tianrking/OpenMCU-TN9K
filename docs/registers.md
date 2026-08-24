# OpenMCU v0.3 register reference

All v0 MMIO registers are 32-bit little-endian and word-aligned. Addresses are
stable within ABI major version 0. ABI minor 3 adds the I2C0 byte engine to the
previous SPI0, WDT0 and PWM0 blocks. The reviewed machine-readable register
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

## SPI0 — `0x4000_3000`

SPI0 is a compact 8-bit, MSB-first, CPOL=0/CPHA=0 (mode-0) master. A `START`
operation automatically asserts one active-low chip select for exactly one byte
transfer. It is intentionally the low-level engine below a future QSPI/XIP or
DMA controller.

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `DATA` | RW | Write the next TX byte; read the completed RX byte. |
| `0x04` | `STATUS` | RW1C | Bit 0 `BUSY`; bit 1 `DONE`, write one to clear. |
| `0x08` | `CLKDIV` | RW | Bits `15:0`: system clocks per SCK half-period minus one. |
| `0x0C` | `CTRL` | RW | Bit 0 `ENABLE`; bit 1 `DONE_IRQ_ENABLE`. |
| `0x10` | `START` | WO | Bit 0 starts a transfer if `ENABLE=1` and `BUSY=0`. |

## I2C0 — `0x4000_4000`

I2C0 is an open-drain, single-master byte engine. `SCL` and `SDA` outputs tell
the platform when to drive a line low; the platform must provide pull-ups,
open-drain pads and synchronized line inputs. Each `CMD` write issues exactly
one operation, allowing software to compose address/write/repeated-START/read
transactions explicitly. The engine honours target clock stretching whenever
it releases SCL. It intentionally has no FIFO, DMA, arbitration-loss handling,
bus-recovery sequencer or automatic timeout; a product application should use
its watchdog/outer timeout policy if a target holds the bus forever.

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `DATA` | RW | Write the next TX byte; read the completed RX byte. |
| `0x04` | `STATUS` | RW1C | Bit 0 `BUSY`; bit 1 `DONE` (W1C); bit 2 `ACK_ERROR` (W1C, target NACK after `WRITE`); bit 3 `COMMAND_ERROR` (W1C); bit 4 `BUS_ACTIVE` (RO). |
| `0x08` | `CLKDIV` | RW | Bits `15:0`: SCL low/high phase in system clocks minus one; reset `134` produces approximately 100 kHz at 27 MHz without stretching. |
| `0x0C` | `CTRL` | RW | Bit 0 `ENABLE`; bit 1 `DONE_IRQ_ENABLE`. Disabling releases both lines and abandons an active transaction. |
| `0x10` | `CMD` | WO | Write exactly one of bit 0 `START`, 1 `STOP`, 2 `WRITE`, 3 `READ_ACK`, 4 `READ_NACK`. `WRITE`/`READ_*`/`STOP` require a preceding START; a second `START` is a repeated START. |

`DONE` is set when a command reaches a terminal result, including an immediate
rejected command. `COMMAND_ERROR` is set for an invalid or out-of-sequence
command; `ACK_ERROR` is set when the target leaves SDA high on a byte-write ACK
clock. While `BUS_ACTIVE` is one the controller holds SCL low between commands,
so software cannot accidentally generate a STOP while it is preparing the next
byte.

## WDT0 — `0x4000_5000`

The watchdog runs from the SoC clock. On expiry it latches `EXPIRED`, can assert
an IRQ, and can emit a one-cycle reset request to the platform reset sequencer.
The Tang bring-up wrapper stretches that request into a normal MCU reset;
software should feed with the documented magic value, not by writing the count.

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | RW | Bit 0 `ENABLE`, bit 1 `RESET_ENABLE`, bit 2 `IRQ_ENABLE`. |
| `0x04` | `TIMEOUT` | RW | Expire when the running count reaches this value. |
| `0x08` | `FEED` | WO | Write `0x51F15EED` to restart the count. |
| `0x0C` | `STATUS` | RW1C | Bit 0 `EXPIRED`; bit 1 is an active `RESET_REQUEST` pulse. |

## PWM0 — `0x4000_6000`

PWM0 is one edge-aligned output. It is high while `COUNT < DUTY`; `PERIOD` is
an inclusive top value, so the full cycle contains `PERIOD + 1` counter ticks.
The raw output is presently a SoC/platform signal; choosing a Tang header or
ASIC pad is a separate board binding, not an implicit pin promise.

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `CTRL` | RW | Bit 0 `ENABLE`; bit 1 `INVERT`. |
| `0x04` | `PRESCALE` | RW | Bits `15:0`: system clocks per PWM tick minus one. |
| `0x08` | `PERIOD` | RW | Inclusive counter top. |
| `0x0C` | `DUTY` | RW | Active-high count limit. |
| `0x10` | `COUNT` | RO | Current PWM counter. |

## SYSCTRL — `0x4000_F000`

| Offset | Register | Access | Meaning |
| --- | --- | --- | --- |
| `0x00` | `CHIP_ID` | RO | `0x4F4D4355` (`OMCU`) |
| `0x04` | `ABI` | RO | ABI major in bits `31:16`, minor in bits `15:0` (`0.3`) |
| `0x08` | `FEATURES` | RO | Bit 0 GPIO0, 1 UART0, 2 TIMER0, 3 SPI0, 4 I2C0, 5 WDT0, 6 PWM0 |
| `0x0C` | `BUILD_ID` | RO | Platform build identifier |
| `0x10` | `MEMORY_KIB` | RO | SRAM KiB in bits `31:16`, ROM KiB in bits `15:0` |

Applications should check `CHIP_ID`, ABI major and required feature bits before
using optional hardware. `omcu_hw_abi_is_compatible()` provides the first C
helper for that check.
