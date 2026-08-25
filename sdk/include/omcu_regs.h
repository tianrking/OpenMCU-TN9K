#ifndef OMCU_REGS_H_
#define OMCU_REGS_H_

/*
 * Generated from spec/omcu-v0.json by scripts/generate-sdk.ps1.
 * Do not hand-edit this file; change the reviewed specification instead.
 * MMIO configuration, command and W1C writes require an aligned 32-bit store.
 * Byte/halfword MMIO writes are ignored unless a register explicitly documents an exception.
 */

#include <stdint.h>

#define OMCU_ROM_BASE            UINT32_C(0x00000000)
#define OMCU_SRAM_BASE           UINT32_C(0x10000000)
#define OMCU_USER_FLASH_BASE     UINT32_C(0x20000000)
#define OMCU_QSPI_XIP_BASE       UINT32_C(0x20000000)
#define OMCU_GPIO0_BASE          UINT32_C(0x40000000)
#define OMCU_UART0_BASE          UINT32_C(0x40001000)
#define OMCU_TIMER0_BASE         UINT32_C(0x40002000)
#define OMCU_SPI0_BASE           UINT32_C(0x40003000)
#define OMCU_I2C0_BASE           UINT32_C(0x40004000)
#define OMCU_WDT0_BASE           UINT32_C(0x40005000)
#define OMCU_PWM0_BASE           UINT32_C(0x40006000)
#define OMCU_IRQCTRL_BASE        UINT32_C(0x40007000)
#define OMCU_UART1_BASE          UINT32_C(0x40008000)
#define OMCU_TIMER1_BASE         UINT32_C(0x40009000)
#define OMCU_PWM1_BASE           UINT32_C(0x4000A000)
#define OMCU_PINMUX_BASE         UINT32_C(0x4000B000)
#define OMCU_ALARM0_BASE         UINT32_C(0x4000C000)
#define OMCU_PULSE0_BASE         UINT32_C(0x4000D000)
#define OMCU_FAULT0_BASE         UINT32_C(0x4000E000)
#define OMCU_SYSCTRL_BASE        UINT32_C(0x4000F000)

#define OMCU_HW_ABI_MAJOR      0u
#define OMCU_HW_ABI_MINOR      8u

#define OMCU_CHIP_ID             UINT32_C(0x4F4D4355)
#define OMCU_SYSCTRL_ABI_MAJOR_SHIFT 16u
#define OMCU_SYSCTRL_ABI_MAJOR_MASK UINT32_C(0xFFFF0000)
#define OMCU_SYSCTRL_ABI_MINOR_MASK UINT32_C(0x0000FFFF)

typedef struct {
  volatile uint32_t out; /* +0x00: output latch */
  volatile uint32_t out_set; /* +0x04: write-one-to-set */
  volatile uint32_t out_clr; /* +0x08: write-one-to-clear */
  volatile uint32_t out_xor; /* +0x0c: write-one-to-toggle */
  volatile uint32_t oe; /* +0x10: output-enable latch */
  volatile uint32_t oe_set; /* +0x14: write-one-to-set */
  volatile uint32_t oe_clr; /* +0x18: write-one-to-clear */
  uint32_t _reserved_1c;
  volatile const uint32_t in; /* +0x20: sampled input */
  volatile uint32_t rise_en; /* +0x24: rising-edge interrupt enable */
  volatile uint32_t fall_en; /* +0x28: falling-edge interrupt enable */
  volatile uint32_t irq_status; /* +0x2c: write-one-to-clear */
  volatile const uint32_t filter_mask; /* +0x30: static scope: all implemented GPIO inputs use the common synchronizer/filter path; writes ignored */
  volatile uint32_t filter_cycles; /* +0x34: low 8 bits: whole-GPIO-port filter; N accepts after N+1 unchanged synchronized port samples */
  volatile uint32_t snapshot_ctrl; /* +0x38: enable, GPIO0 IRQ enable and first-event/overwrite policy */
  volatile uint32_t snapshot_rise_en; /* +0x3c: alias of RISE_EN: coherent rising GPIO IRQ and snapshot trigger mask */
  volatile uint32_t snapshot_fall_en; /* +0x40: alias of FALL_EN: coherent falling GPIO IRQ and snapshot trigger mask */
  volatile uint32_t snapshot_status; /* +0x44: VALID and OVERFLOW write-one-to-clear; FORCED marks a priority FAULT0 context capture */
  volatile const uint32_t snapshot_event; /* +0x48: selected edge bit mask captured with the snapshot */
  volatile const uint32_t snapshot_input; /* +0x4c: filtered GPIO input level captured with the snapshot */
  volatile const uint32_t snapshot_irq; /* +0x50: IRQCTRL active CPU IRQ mask captured with the snapshot */
  volatile const uint32_t snapshot_reset; /* +0x54: retained reset-cause value captured with the snapshot */
  volatile const uint32_t snapshot_ticks; /* +0x58: low 32 bits of SYSCTRL run ticks captured with the snapshot */
} omcu_gpio_regs_t;

typedef struct {
  volatile uint32_t data; /* +0x00: low 8 bits: TX byte on full 32-bit write / RX byte on read */
  volatile uint32_t status; /* +0x04: TX ready, RX valid and sticky errors */
  volatile uint32_t bauddiv; /* +0x08: system clocks per UART bit minus one */
  volatile uint32_t ctrl; /* +0x0c: TX enable, RX enable, RX IRQ enable */
} omcu_uart_regs_t;

typedef struct {
  volatile uint32_t data; /* +0x00: low 8 bits: TX byte on full 32-bit write / RX byte on read */
  volatile uint32_t status; /* +0x04: TX ready, RX valid and sticky errors */
  volatile uint32_t bauddiv; /* +0x08: system clocks per UART bit minus one */
  volatile uint32_t ctrl; /* +0x0c: TX enable, RX enable, RX IRQ enable */
} omcu_uart1_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: EN, IRQ_EN, AUTO_RELOAD */
  volatile uint32_t prescale; /* +0x04: 16-bit divider minus one */
  volatile uint32_t count; /* +0x08: current counter */
  volatile uint32_t compare; /* +0x0c: compare value */
  volatile uint32_t status; /* +0x10: pending, write-one-to-clear */
} omcu_timer_regs_t;

typedef struct {
  volatile uint32_t data; /* +0x00: low 8 bits: TX byte on full 32-bit write / RX byte on read */
  volatile uint32_t status; /* +0x04: BUSY, DONE W1C and CS_ACTIVE */
  volatile uint32_t clkdiv; /* +0x08: SCK half-period in system clocks minus one */
  volatile uint32_t ctrl; /* +0x0c: ENABLE, DONE interrupt enable and explicit multi-byte CS hold */
  volatile uint32_t start; /* +0x10: write one to start one automatic mode-0 byte transfer */
} omcu_spi_regs_t;

typedef struct {
  volatile uint32_t data; /* +0x00: low 8 bits: TX byte on full 32-bit write / RX byte on read */
  volatile uint32_t status; /* +0x04: BUSY, DONE W1C, ACK_ERROR W1C, COMMAND_ERROR W1C and BUS_ACTIVE */
  volatile uint32_t clkdiv; /* +0x08: SCL low/high phase in system clocks minus one */
  volatile uint32_t ctrl; /* +0x0c: ENABLE and DONE interrupt enable */
  volatile uint32_t cmd; /* +0x10: write exactly one command bit: START, STOP, WRITE, READ_ACK or READ_NACK */
} omcu_i2c_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: legacy enable/reset/expiry IRQ plus pretimeout, window and heartbeat supervisor controls */
  volatile uint32_t timeout; /* +0x04: watchdog count limit before expiry */
  volatile uint32_t feed; /* +0x08: write OMCU_WDT_FEED_MAGIC to restart the watchdog count */
  volatile uint32_t status; /* +0x0c: expiry/pretimeout/window/heartbeat/rejected-feed diagnostics, sticky W1C except reset pulse */
  volatile uint32_t pretimeout; /* +0x10: warning count; zero disables pretimeout stage; full 32-bit writes only */
  volatile uint32_t window_min; /* +0x14: minimum count before a valid feed when window supervisor is enabled; full 32-bit writes only */
  volatile uint32_t heartbeat_required; /* +0x18: low 8 bits: software task heartbeat mask required before feed; full 32-bit writes only */
  volatile const uint32_t heartbeat_seen; /* +0x1c: low 8 bits: accumulated heartbeat bits in current watchdog epoch */
  volatile uint32_t heartbeat_kick; /* +0x20: low 8 bits write-one-to-set task heartbeat bits */
  volatile const uint32_t count; /* +0x24: current watchdog count for diagnostics */
} omcu_wdt_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: ENABLE and INVERT */
  volatile uint32_t prescale; /* +0x04: PWM counter clocks minus one */
  volatile uint32_t period; /* +0x08: inclusive PWM counter top */
  volatile uint32_t duty; /* +0x0c: output high while COUNT is strictly lower than DUTY */
  volatile const uint32_t count; /* +0x10: current PWM counter */
} omcu_pwm_regs_t;

typedef struct {
  volatile const uint32_t pending; /* +0x00: sticky and current source bits in CPU IRQ positions */
  volatile uint32_t enable; /* +0x04: per-source IRQ enable mask in CPU IRQ positions */
  volatile uint32_t clear; /* +0x08: write-one-to-clear sticky and software-pending source bits */
  volatile uint32_t force; /* +0x0c: write-one-to-set software-pending source bits */
  volatile const uint32_t active; /* +0x10: enabled pending source bits sent to the CPU */
  volatile const uint32_t highest; /* +0x14: lowest numbered active CPU IRQ bit, zero when none */
} omcu_irqctrl_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: shared enable and per-channel invert bits */
  volatile uint32_t prescale; /* +0x04: shared PWM counter clocks minus one */
  volatile uint32_t period; /* +0x08: low 16 bits: inclusive shared PWM counter top */
  volatile uint32_t duty0; /* +0x0c: low 16 bits: channel 0 high while shared COUNT is strictly lower */
  volatile uint32_t duty1; /* +0x10: low 16 bits: channel 1 high while shared COUNT is strictly lower */
  volatile uint32_t duty2; /* +0x14: low 16 bits: channel 2 high while shared COUNT is strictly lower */
  volatile uint32_t duty3; /* +0x18: low 16 bits: channel 3 high while shared COUNT is strictly lower */
  volatile const uint32_t count; /* +0x1c: low 16 bits: current shared PWM counter */
} omcu_pwm1_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: timer, capture and quadrature enable/configuration bits */
  volatile uint32_t prescale; /* +0x04: timer clocks per count minus one */
  volatile uint32_t count; /* +0x08: low 16 bits: current capture timestamp counter */
  volatile uint32_t compare; /* +0x0c: low 16 bits: compare value for timer event */
  volatile uint32_t filter; /* +0x10: low 8 bits: consecutive mismatched synchronized samples required minus zero */
  volatile const uint32_t capture_a; /* +0x14: low 16 bits: timestamp of latest configured channel A edge */
  volatile const uint32_t capture_b; /* +0x18: low 16 bits: timestamp of latest configured channel B edge */
  volatile uint32_t encoder; /* +0x1c: low 16 bits: wrapping signed quadrature position accumulator */
  volatile uint32_t status; /* +0x20: event pending W1C plus filtered input and direction observation */
} omcu_timer1_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: alternate-function ownership; disabled functions leave pads under GPIO control */
} omcu_pinmux_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: bit0 gates the two parallel compare channels; bit1 reports the shared TIMER0 timebase running */
  volatile const uint32_t prescale; /* +0x04: low 16 bits: read-only mirror of TIMER0 prescale */
  volatile const uint32_t count; /* +0x08: low 16 bits: read-only mirror of TIMER0 wrapping count */
  volatile uint32_t channel_enable; /* +0x0c: bits 0..1 arm the two independent compare channels; full 32-bit writes only */
  volatile uint32_t irq_enable; /* +0x10: bits 0..1 select pending channels that assert ALARM0 IRQ; full 32-bit writes only */
  volatile uint32_t periodic; /* +0x14: bits 0..1 advance compare by PERIODn after an event; full 32-bit writes only */
  volatile uint32_t pending; /* +0x18: bits 0..1 compare pending, write-one-to-clear; full 32-bit writes only */
  volatile uint32_t compare0; /* +0x1c: low 16 bits: absolute shared-count deadline for channel 0; full 32-bit writes only */
  volatile uint32_t compare1; /* +0x20: low 16 bits: absolute shared-count deadline for channel 1; full 32-bit writes only */
  volatile const uint32_t compare2; /* +0x24: reserved read-zero slot; this Tang Nano 9K profile implements two alarms */
  volatile const uint32_t compare3; /* +0x28: reserved read-zero slot; this Tang Nano 9K profile implements two alarms */
  volatile uint32_t period0; /* +0x2c: low 16 bits: periodic increment for channel 0; zero is one-shot-safe; full 32-bit writes only */
  volatile uint32_t period1; /* +0x30: low 16 bits: periodic increment for channel 1; zero is one-shot-safe; full 32-bit writes only */
  volatile const uint32_t period2; /* +0x34: reserved read-zero slot; this Tang Nano 9K profile implements two alarms */
  volatile const uint32_t period3; /* +0x38: reserved read-zero slot; this Tang Nano 9K profile implements two alarms */
} omcu_alarm_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: capture engine enable and aggregate IRQ enable; full 32-bit writes only */
  volatile uint32_t input_select; /* +0x04: one selected physical input: 0=GPIO0/J5.8, 1=GPIO1/J5.9, 2=GPIO2/J5.10; change clears epoch; full 32-bit writes only */
  volatile uint32_t edge; /* +0x08: bit 0 selects falling instead of rising edge; full 32-bit writes only */
  volatile uint32_t filter; /* +0x0c: low 8 bits: N+1 mismatched synchronized samples required; full 32-bit writes only */
  volatile uint32_t status; /* +0x10: bit0 pending W1C, bit1 filtered selected input, bit2 period valid, bits5..4 selected input; full 32-bit writes only */
  volatile uint32_t clear; /* +0x14: bit0 clears selected-input count, period, tick, valid and pending epoch; full 32-bit writes only */
  volatile const uint32_t count; /* +0x18: low 16 bits: wrapping selected-edge count */
  volatile const uint32_t period; /* +0x1c: low 16 bits: run-tick distance between most recent two selected edges */
  volatile const uint32_t last_tick; /* +0x20: low 16 bits: run-tick timestamp of most recent selected edge */
} omcu_pulse_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: enable, polarity, IRQ and PWM/GPIO safety-gate selection; full 32-bit writes only */
  volatile uint32_t filter; /* +0x04: low 8 bits: consecutive mismatched synchronized samples required minus zero; full 32-bit writes only */
  volatile const uint32_t gpio_hiz_mask; /* +0x08: fixed conservative profile: all reviewed GPIO output-enable bits go high impedance after a trip; writes ignored */
  volatile uint32_t status; /* +0x0c: TRIPPED, filtered input, pinmux claim and clear-rejected diagnostic; full 32-bit W1C write */
  volatile uint32_t clear; /* +0x10: exact full-word OMCU_FAULT_CLEAR_MAGIC clears only an inactive claimed input */
  volatile const uint32_t snapshot_tick; /* +0x14: low 32-bit SYSCTRL run-tick timestamp of first trip */
  volatile const uint32_t snapshot_gpio; /* +0x18: GPIO input snapshot at first trip */
  volatile const uint32_t snapshot_irq; /* +0x1c: IRQCTRL active CPU IRQ mask at first trip */
  volatile const uint32_t snapshot_reset; /* +0x20: retained reset cause at first trip */
} omcu_fault_regs_t;

typedef struct {
  volatile const uint32_t chip_id; /* +0x00: OpenMCU chip identifier */
  volatile const uint32_t abi; /* +0x04: major in bits 31:16, minor in bits 15:0 */
  volatile const uint32_t features; /* +0x08: implemented peripheral feature bits */
  volatile const uint32_t build_id; /* +0x0c: platform build identifier */
  volatile const uint32_t memory_kib; /* +0x10: SRAM KiB in bits 31:16, ROM KiB in bits 15:0 */
  volatile const uint32_t reset_cause; /* +0x14: last retained reset cause one-hot value */
  volatile const uint32_t run_ticks_lo; /* +0x18: low 32 bits of 64-bit SoC-running clock tick counter */
  volatile const uint32_t run_ticks_hi; /* +0x1c: high 32 bits of 64-bit SoC-running clock tick counter */
  volatile const uint32_t reset_count; /* +0x20: retained watchdog/software reset count since external reset */
  volatile uint32_t boot_ctrl; /* +0x24: bootloader request pending/support status plus exact full-word request/ack commands */
} omcu_sysctrl_regs_t;

#define OMCU_GPIO0               ((omcu_gpio_regs_t *)(uintptr_t)OMCU_GPIO0_BASE)
#define OMCU_UART0               ((omcu_uart_regs_t *)(uintptr_t)OMCU_UART0_BASE)
#define OMCU_UART1               ((omcu_uart1_regs_t *)(uintptr_t)OMCU_UART1_BASE)
#define OMCU_TIMER0              ((omcu_timer_regs_t *)(uintptr_t)OMCU_TIMER0_BASE)
#define OMCU_SPI0                ((omcu_spi_regs_t *)(uintptr_t)OMCU_SPI0_BASE)
#define OMCU_I2C0                ((omcu_i2c_regs_t *)(uintptr_t)OMCU_I2C0_BASE)
#define OMCU_WDT0                ((omcu_wdt_regs_t *)(uintptr_t)OMCU_WDT0_BASE)
#define OMCU_PWM0                ((omcu_pwm_regs_t *)(uintptr_t)OMCU_PWM0_BASE)
#define OMCU_IRQCTRL             ((omcu_irqctrl_regs_t *)(uintptr_t)OMCU_IRQCTRL_BASE)
#define OMCU_PWM1                ((omcu_pwm1_regs_t *)(uintptr_t)OMCU_PWM1_BASE)
#define OMCU_TIMER1              ((omcu_timer1_regs_t *)(uintptr_t)OMCU_TIMER1_BASE)
#define OMCU_PINMUX              ((omcu_pinmux_regs_t *)(uintptr_t)OMCU_PINMUX_BASE)
#define OMCU_ALARM0              ((omcu_alarm_regs_t *)(uintptr_t)OMCU_ALARM0_BASE)
#define OMCU_PULSE0              ((omcu_pulse_regs_t *)(uintptr_t)OMCU_PULSE0_BASE)
#define OMCU_FAULT0              ((omcu_fault_regs_t *)(uintptr_t)OMCU_FAULT0_BASE)
#define OMCU_SYSCTRL             ((omcu_sysctrl_regs_t *)(uintptr_t)OMCU_SYSCTRL_BASE)

enum {
  OMCU_FEATURE_GPIO0               = 1u << 0,
  OMCU_FEATURE_UART0               = 1u << 1,
  OMCU_FEATURE_TIMER0              = 1u << 2,
  OMCU_FEATURE_SPI0                = 1u << 3,
  OMCU_FEATURE_I2C0                = 1u << 4,
  OMCU_FEATURE_WDT0                = 1u << 5,
  OMCU_FEATURE_PWM0                = 1u << 6,
  OMCU_FEATURE_IRQCTRL             = 1u << 7,
  OMCU_FEATURE_UART1               = 1u << 8,
  OMCU_FEATURE_TIMER1              = 1u << 9,
  OMCU_FEATURE_PWM1                = 1u << 10,
  OMCU_FEATURE_DIAGNOSTICS         = 1u << 11,
  OMCU_FEATURE_PINMUX              = 1u << 12,
  OMCU_FEATURE_GPIO_EXPANSION      = 1u << 13,
  OMCU_FEATURE_USER_FLASH          = 1u << 14,
  OMCU_FEATURE_GPIO_RELIABILITY    = 1u << 15,
  OMCU_FEATURE_ALARM0              = 1u << 16,
  OMCU_FEATURE_PULSE0              = 1u << 17,
  OMCU_FEATURE_FAULT0              = 1u << 18,
  OMCU_FEATURE_WDT_SUPERVISOR      = 1u << 19,
  OMCU_RESET_CAUSE_EXTERNAL        = 1u << 0,
  OMCU_RESET_CAUSE_WATCHDOG        = 1u << 1,
  OMCU_RESET_CAUSE_SOFTWARE        = 1u << 2,
  OMCU_SYSCTRL_BOOT_CTRL_REQUEST_PENDING = 1u << 0,
  OMCU_SYSCTRL_BOOT_CTRL_REQUEST_SUPPORTED = 1u << 1,
  OMCU_SYSCTRL_BOOT_REQUEST_MAGIC  = UINT32_C(0xB00710AD),
  OMCU_SYSCTRL_BOOT_REQUEST_ACK_MAGIC = UINT32_C(0xACCE5501),
  OMCU_IRQ_GPIO0                   = 1u << 8,
  OMCU_IRQ_UART0                   = 1u << 9,
  OMCU_IRQ_TIMER0                  = 1u << 10,
  OMCU_IRQ_SPI0                    = 1u << 11,
  OMCU_IRQ_I2C0                    = 1u << 12,
  OMCU_IRQ_WDT0                    = 1u << 13,
  OMCU_IRQ_UART1                   = 1u << 14,
  OMCU_IRQ_TIMER1                  = 1u << 15,
  OMCU_IRQ_ALARM0                  = 1u << 16,
  OMCU_IRQ_PULSE0                  = 1u << 17,
  OMCU_IRQ_FAULT0                  = 1u << 18,
  OMCU_IRQ_EXTERNAL_MASK           = UINT32_C(0x0007FF00),
  OMCU_PINMUX_CTRL_UART1_ENABLE    = 1u << 0,
  OMCU_PINMUX_CTRL_PWM1_ENABLE     = 1u << 1,
  OMCU_PINMUX_CTRL_TIMER1_ENABLE   = 1u << 2,
  OMCU_PINMUX_CTRL_PULSE0_ENABLE   = 1u << 3,
  OMCU_PINMUX_CTRL_FAULT0_ENABLE   = 1u << 4,
  OMCU_GPIO_FILTER_CYCLES_MASK     = UINT32_C(0x000000FF),
  OMCU_GPIO_SNAPSHOT_CTRL_ENABLE   = 1u << 0,
  OMCU_GPIO_SNAPSHOT_CTRL_IRQ_ENABLE = 1u << 1,
  OMCU_GPIO_SNAPSHOT_CTRL_OVERWRITE = 1u << 2,
  OMCU_GPIO_SNAPSHOT_STATUS_VALID  = 1u << 0,
  OMCU_GPIO_SNAPSHOT_STATUS_OVERFLOW = 1u << 1,
  OMCU_GPIO_SNAPSHOT_STATUS_FORCED = 1u << 2,
  OMCU_TIMER_CTRL_ENABLE           = 1u << 0,
  OMCU_TIMER_CTRL_IRQ_ENABLE       = 1u << 1,
  OMCU_TIMER_CTRL_AUTO_RELOAD      = 1u << 2,
  OMCU_TIMER_STATUS_PENDING        = 1u << 0,
  OMCU_ALARM_CHANNEL_COUNT         = 2u,
  OMCU_ALARM_CHANNEL_MASK          = UINT32_C(0x00000003),
  OMCU_ALARM_CTRL_ENABLE           = 1u << 0,
  OMCU_PULSE_INPUT_COUNT           = 3u,
  OMCU_PULSE_INPUT_MASK            = UINT32_C(0x00000003),
  OMCU_PULSE_CTRL_ENABLE           = 1u << 0,
  OMCU_PULSE_CTRL_IRQ_ENABLE       = 1u << 1,
  OMCU_PULSE_EDGE_FALLING          = 1u << 0,
  OMCU_PULSE_STATUS_PENDING        = 1u << 0,
  OMCU_PULSE_STATUS_FILTERED_INPUT = 1u << 1,
  OMCU_PULSE_STATUS_PERIOD_VALID   = 1u << 2,
  OMCU_PULSE_STATUS_INPUT_SELECT_SHIFT = 4u,
  OMCU_PULSE_STATUS_INPUT_SELECT_MASK = UINT32_C(0x00000030),
  OMCU_PULSE_CLEAR_EPOCH           = 1u << 0,
  OMCU_SPI_CTRL_ENABLE             = 1u << 0,
  OMCU_SPI_CTRL_IRQ_ENABLE         = 1u << 1,
  OMCU_SPI_CTRL_CS_HOLD            = 1u << 2,
  OMCU_SPI_STATUS_BUSY             = 1u << 0,
  OMCU_SPI_STATUS_DONE             = 1u << 1,
  OMCU_SPI_STATUS_CS_ACTIVE        = 1u << 5,
  OMCU_I2C_CTRL_ENABLE             = 1u << 0,
  OMCU_I2C_CTRL_IRQ_ENABLE         = 1u << 1,
  OMCU_I2C_STATUS_BUSY             = 1u << 0,
  OMCU_I2C_STATUS_DONE             = 1u << 1,
  OMCU_I2C_STATUS_ACK_ERROR        = 1u << 2,
  OMCU_I2C_STATUS_COMMAND_ERROR    = 1u << 3,
  OMCU_I2C_STATUS_BUS_ACTIVE       = 1u << 4,
  OMCU_I2C_CMD_START               = 1u << 0,
  OMCU_I2C_CMD_STOP                = 1u << 1,
  OMCU_I2C_CMD_WRITE               = 1u << 2,
  OMCU_I2C_CMD_READ_ACK            = 1u << 3,
  OMCU_I2C_CMD_READ_NACK           = 1u << 4,
  OMCU_WDT_CTRL_ENABLE             = 1u << 0,
  OMCU_WDT_CTRL_RESET_ENABLE       = 1u << 1,
  OMCU_WDT_CTRL_IRQ_ENABLE         = 1u << 2,
  OMCU_WDT_CTRL_PRETIMEOUT_IRQ_ENABLE = 1u << 3,
  OMCU_WDT_CTRL_WINDOW_ENABLE      = 1u << 4,
  OMCU_WDT_CTRL_HEARTBEAT_ENABLE   = 1u << 5,
  OMCU_WDT_STATUS_EXPIRED          = 1u << 0,
  OMCU_WDT_STATUS_RESET_REQUEST    = 1u << 1,
  OMCU_WDT_STATUS_PRETIMEOUT       = 1u << 2,
  OMCU_WDT_STATUS_WINDOW_VIOLATION = 1u << 3,
  OMCU_WDT_STATUS_HEARTBEAT_MISSING = 1u << 4,
  OMCU_WDT_STATUS_FEED_REJECTED    = 1u << 5,
  OMCU_WDT_HEARTBEAT_MASK          = UINT32_C(0x000000FF),
  OMCU_WDT_FEED_MAGIC              = UINT32_C(0x51F15EED),
  OMCU_FAULT_FILTER_MASK           = UINT32_C(0x000000FF),
  OMCU_FAULT_CTRL_ENABLE           = 1u << 0,
  OMCU_FAULT_CTRL_ACTIVE_HIGH      = 1u << 1,
  OMCU_FAULT_CTRL_IRQ_ENABLE       = 1u << 2,
  OMCU_FAULT_CTRL_GATE_PWM0        = 1u << 3,
  OMCU_FAULT_CTRL_GATE_PWM1        = 1u << 4,
  OMCU_FAULT_CTRL_GATE_GPIO        = 1u << 5,
  OMCU_FAULT_STATUS_TRIPPED        = 1u << 0,
  OMCU_FAULT_STATUS_FILTERED_INPUT = 1u << 1,
  OMCU_FAULT_STATUS_INPUT_CLAIMED  = 1u << 2,
  OMCU_FAULT_STATUS_CLEAR_REJECTED = 1u << 3,
  OMCU_FAULT_STATUS_ACTIVE         = 1u << 4,
  OMCU_FAULT_CLEAR_MAGIC           = UINT32_C(0xFA17C1EA),
  OMCU_PWM_CTRL_ENABLE             = 1u << 0,
  OMCU_PWM_CTRL_INVERT             = 1u << 1,
  OMCU_PWM1_CHANNEL_COUNT          = 4u,
  OMCU_PWM1_VALUE_MASK             = UINT32_C(0x0000FFFF),
  OMCU_PWM1_CTRL_ENABLE            = 1u << 0,
  OMCU_PWM1_CTRL_INVERT_SHIFT      = 4u,
  OMCU_PWM1_CTRL_INVERT_MASK       = UINT32_C(0x000000F0),
  OMCU_TIMER1_CTRL_ENABLE          = 1u << 0,
  OMCU_TIMER1_VALUE_MASK           = UINT32_C(0x0000FFFF),
  OMCU_TIMER1_FILTER_MASK          = UINT32_C(0x000000FF),
  OMCU_TIMER1_CTRL_IRQ_ENABLE      = 1u << 1,
  OMCU_TIMER1_CTRL_AUTO_RELOAD     = 1u << 2,
  OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE = 1u << 3,
  OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE = 1u << 4,
  OMCU_TIMER1_CTRL_CAPTURE_A_FALLING = 1u << 5,
  OMCU_TIMER1_CTRL_CAPTURE_B_FALLING = 1u << 6,
  OMCU_TIMER1_CTRL_QUADRATURE_ENABLE = 1u << 7,
  OMCU_TIMER1_CTRL_QUADRATURE_REVERSE = 1u << 8,
  OMCU_TIMER1_STATUS_COMPARE       = 1u << 0,
  OMCU_TIMER1_STATUS_CAPTURE_A     = 1u << 1,
  OMCU_TIMER1_STATUS_CAPTURE_B     = 1u << 2,
  OMCU_TIMER1_STATUS_ENCODER_STEP  = 1u << 3,
  OMCU_TIMER1_STATUS_ENCODER_ILLEGAL = 1u << 4,
  OMCU_TIMER1_STATUS_INPUT_A       = 1u << 5,
  OMCU_TIMER1_STATUS_INPUT_B       = 1u << 6,
  OMCU_TIMER1_STATUS_ENCODER_DIRECTION = 1u << 7,
};

#endif  /* OMCU_REGS_H_ */
