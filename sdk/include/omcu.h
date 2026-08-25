#ifndef OMCU_H_
#define OMCU_H_

/*
 * OpenMCU public v0 device header.
 *
 * This header is intentionally compiler-light: it works with a normal
 * riscv32-unknown-elf C compiler and does not depend on a vendor SDK.
 */

#include "omcu_regs.h"

#include <stdbool.h>

enum {
  OMCU_UART_CTRL_TX_ENABLE = 1u << 0,
  OMCU_UART_CTRL_RX_ENABLE = 1u << 1,
  OMCU_UART_CTRL_RX_IRQ_ENABLE = 1u << 2,
  OMCU_UART_STATUS_TX_READY = 1u << 0,
  OMCU_UART_STATUS_RX_VALID = 1u << 1,
  OMCU_UART_STATUS_RX_OVERRUN = 1u << 2,
  OMCU_UART_STATUS_RX_FRAMING_ERROR = 1u << 3,
};

static inline bool omcu_hw_abi_is_compatible(uint16_t expected_major) {
  return OMCU_SYSCTRL->chip_id == OMCU_CHIP_ID &&
         (uint16_t)(OMCU_SYSCTRL->abi >> OMCU_SYSCTRL_ABI_MAJOR_SHIFT) ==
           expected_major;
}

static inline bool omcu_hw_has_feature(uint32_t feature) {
  return (OMCU_SYSCTRL->features & feature) == feature;
}

/*
 * SYSCTRL diagnostics are intentionally feature-gated: a v0-compatible
 * smaller fabric can retain the identity registers while omitting the board
 * reset sequencer that supplies meaningful cause/count values.
 */
static inline bool omcu_sysctrl_has_diagnostics(void) {
  return omcu_hw_has_feature(OMCU_FEATURE_DIAGNOSTICS);
}

static inline uint32_t omcu_sysctrl_reset_cause(void) {
  return OMCU_SYSCTRL->reset_cause;
}

static inline uint32_t omcu_sysctrl_reset_count(void) {
  return OMCU_SYSCTRL->reset_count;
}

/* Read a stable 64-bit tick snapshot on the 32-bit CPU, including rollover. */
static inline uint64_t omcu_sysctrl_run_ticks(void) {
  uint32_t high_before;
  uint32_t low;
  uint32_t high_after;

  do {
    high_before = OMCU_SYSCTRL->run_ticks_hi;
    low = OMCU_SYSCTRL->run_ticks_lo;
    high_after = OMCU_SYSCTRL->run_ticks_hi;
  } while (high_before != high_after);
  return ((uint64_t)high_after << 32u) | (uint64_t)low;
}

/*
 * A software Bootloader request exists only in a product configuration with
 * a retained reset sequencer and User Flash.  A successful return means the
 * command was issued; the caller must not rely on any following instructions
 * running because the top-level reset sequence will restart the SoC shortly.
 */
static inline bool omcu_bootloader_request_supported(void) {
  return omcu_sysctrl_has_diagnostics() &&
         (OMCU_SYSCTRL->boot_ctrl &
          OMCU_SYSCTRL_BOOT_CTRL_REQUEST_SUPPORTED) != 0u;
}

static inline bool omcu_bootloader_request_pending(void) {
  return omcu_bootloader_request_supported() &&
         (OMCU_SYSCTRL->boot_ctrl &
          OMCU_SYSCTRL_BOOT_CTRL_REQUEST_PENDING) != 0u;
}

static inline bool omcu_request_bootloader(void) {
  if (!omcu_bootloader_request_supported()) {
    return false;
  }
  OMCU_SYSCTRL->boot_ctrl = OMCU_SYSCTRL_BOOT_REQUEST_MAGIC;
  return true;
}

/* Intended for the immutable Boot ROM after it has consumed a pending request. */
static inline bool omcu_bootloader_ack_request(void) {
  if (!omcu_bootloader_request_pending()) {
    return false;
  }
  OMCU_SYSCTRL->boot_ctrl = OMCU_SYSCTRL_BOOT_REQUEST_ACK_MAGIC;
  return true;
}

/*
 * PicoRV32 custom-IRQ control functions implemented by startup/omcu_irq.S.
 * They are intentionally ordinary C ABI functions so applications never need
 * to emit custom opcodes themselves.  The returned mask is the mask that was
 * active before the requested value was installed.
 */
uint32_t omcu_irq_set_mask(uint32_t mask);
uint32_t omcu_irq_wait(void);

/*
 * The startup wrapper calls this function from a dedicated IRQ stack with the
 * complete active CPU IRQ mask.  Applications override the weak SDK default
 * with a strong definition and must clear the originating peripheral before
 * acknowledging its IRQCTRL source.
 */
void omcu_irq_dispatch(uint32_t pending);

static inline uint32_t omcu_irq_global_enable(void) {
  return omcu_irq_set_mask(0u);
}

static inline uint32_t omcu_irq_global_disable(void) {
  return omcu_irq_set_mask(UINT32_MAX);
}

static inline void omcu_irq_restore(uint32_t previous_mask) {
  (void)omcu_irq_set_mask(previous_mask);
}

static inline uint32_t omcu_irqctrl_pending(void) {
  return OMCU_IRQCTRL->pending;
}

static inline uint32_t omcu_irqctrl_active(void) {
  return OMCU_IRQCTRL->active;
}

static inline uint32_t omcu_irqctrl_highest(void) {
  return OMCU_IRQCTRL->highest;
}

static inline void omcu_irqctrl_set_enable(uint32_t mask) {
  OMCU_IRQCTRL->enable = mask & OMCU_IRQ_EXTERNAL_MASK;
}

static inline void omcu_irqctrl_ack(uint32_t mask) {
  OMCU_IRQCTRL->clear = mask & OMCU_IRQ_EXTERNAL_MASK;
}

static inline void omcu_irqctrl_force(uint32_t mask) {
  OMCU_IRQCTRL->force = mask & OMCU_IRQ_EXTERNAL_MASK;
}

static inline void omcu_gpio_enable_output(uint32_t mask) {
  OMCU_GPIO0->oe_set = mask;
}

static inline void omcu_gpio_disable_output(uint32_t mask) {
  OMCU_GPIO0->oe_clr = mask;
}

static inline void omcu_gpio_set(uint32_t mask) {
  OMCU_GPIO0->out_set = mask;
}

static inline void omcu_gpio_clear(uint32_t mask) {
  OMCU_GPIO0->out_clr = mask;
}

static inline void omcu_gpio_toggle(uint32_t mask) {
  OMCU_GPIO0->out_xor = mask;
}

/*
 * GPIO reliable-input profile. FILTER_CYCLES=N accepts a changed level only
 * after N+1 consecutive mismatched samples from the two-flop synchronizer.
 * It is intended for buttons, slow sensors and industrial dry-contact style
 * inputs, not signals whose timing must be measured above the system clock.
 */
static inline bool omcu_gpio_configure_filter(uint32_t mask, uint8_t filter_cycles) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_GPIO_RELIABILITY)) {
    return false;
  }
  OMCU_GPIO0->filter_cycles = (uint32_t)filter_cycles;
  OMCU_GPIO0->filter_mask = mask;
  return true;
}

typedef struct {
  uint32_t event_mask;
  uint32_t input_level;
  uint32_t irq_active;
  uint32_t reset_cause;
  uint32_t run_ticks_lo;
} omcu_gpio_snapshot_t;

/*
 * Arm one first-event GPIO snapshot.  With overwrite=false the first selected
 * edge is retained and a later edge only sets OVERFLOW; this is the recommended
 * small-black-box policy for fault diagnosis. The optional IRQ shares
 * OMCU_IRQ_GPIO0, so its ISR must clear SNAPSHOT_STATUS as well as GPIO IRQ
 * status where applicable.
 */
static inline bool omcu_gpio_snapshot_arm(
  uint32_t rise_mask,
  uint32_t fall_mask,
  bool enable_irq,
  bool overwrite
) {
  uint32_t ctrl = OMCU_GPIO_SNAPSHOT_CTRL_ENABLE;

  if (!omcu_hw_has_feature(OMCU_FEATURE_GPIO_RELIABILITY)) {
    return false;
  }
  if (enable_irq) {
    ctrl |= OMCU_GPIO_SNAPSHOT_CTRL_IRQ_ENABLE;
  }
  if (overwrite) {
    ctrl |= OMCU_GPIO_SNAPSHOT_CTRL_OVERWRITE;
  }
  OMCU_GPIO0->snapshot_ctrl = 0u;
  OMCU_GPIO0->snapshot_status = OMCU_GPIO_SNAPSHOT_STATUS_VALID |
                                OMCU_GPIO_SNAPSHOT_STATUS_OVERFLOW;
  OMCU_GPIO0->snapshot_rise_en = rise_mask;
  OMCU_GPIO0->snapshot_fall_en = fall_mask;
  OMCU_GPIO0->snapshot_ctrl = ctrl;
  return true;
}

static inline bool omcu_gpio_snapshot_read(omcu_gpio_snapshot_t *snapshot) {
  if (snapshot == 0 ||
      (OMCU_GPIO0->snapshot_status & OMCU_GPIO_SNAPSHOT_STATUS_VALID) == 0u) {
    return false;
  }
  snapshot->event_mask = OMCU_GPIO0->snapshot_event;
  snapshot->input_level = OMCU_GPIO0->snapshot_input;
  snapshot->irq_active = OMCU_GPIO0->snapshot_irq;
  snapshot->reset_cause = OMCU_GPIO0->snapshot_reset;
  snapshot->run_ticks_lo = OMCU_GPIO0->snapshot_ticks;
  return true;
}

static inline void omcu_gpio_snapshot_clear(void) {
  OMCU_GPIO0->snapshot_status = OMCU_GPIO_SNAPSHOT_STATUS_VALID |
                                OMCU_GPIO_SNAPSHOT_STATUS_OVERFLOW;
}

static inline void omcu_uart0_init(uint16_t bauddiv, bool enable_rx_irq) {
  OMCU_UART0->ctrl = 0u;
  OMCU_UART0->bauddiv = bauddiv;
  OMCU_UART0->status = OMCU_UART_STATUS_RX_OVERRUN |
                       OMCU_UART_STATUS_RX_FRAMING_ERROR;
  OMCU_UART0->ctrl = OMCU_UART_CTRL_TX_ENABLE |
                    OMCU_UART_CTRL_RX_ENABLE |
                    (enable_rx_irq ? OMCU_UART_CTRL_RX_IRQ_ENABLE : 0u);
}

static inline bool omcu_uart0_tx_ready(void) {
  return (OMCU_UART0->status & OMCU_UART_STATUS_TX_READY) != 0u;
}

static inline void omcu_uart0_write_byte(uint8_t byte) {
  while (!omcu_uart0_tx_ready()) {
  }
  OMCU_UART0->data = byte;
}

static inline bool omcu_uart0_rx_ready(void) {
  return (OMCU_UART0->status & OMCU_UART_STATUS_RX_VALID) != 0u;
}

static inline uint8_t omcu_uart0_read_byte(void) {
  return (uint8_t)OMCU_UART0->data;
}

/*
 * UART1 has the same deliberately small, no-FIFO register contract as
 * UART0.  It is an optional peripheral: board support must also select an
 * approved alternate-function route before its pins become visible.
 */
static inline void omcu_uart1_init(uint16_t bauddiv, bool enable_rx_irq) {
  OMCU_UART1->ctrl = 0u;
  OMCU_UART1->bauddiv = bauddiv;
  OMCU_UART1->status = OMCU_UART_STATUS_RX_OVERRUN |
                       OMCU_UART_STATUS_RX_FRAMING_ERROR;
  OMCU_UART1->ctrl = OMCU_UART_CTRL_TX_ENABLE |
                    OMCU_UART_CTRL_RX_ENABLE |
                    (enable_rx_irq ? OMCU_UART_CTRL_RX_IRQ_ENABLE : 0u);
}

static inline bool omcu_uart1_tx_ready(void) {
  return (OMCU_UART1->status & OMCU_UART_STATUS_TX_READY) != 0u;
}

static inline void omcu_uart1_write_byte(uint8_t byte) {
  while (!omcu_uart1_tx_ready()) {
  }
  OMCU_UART1->data = byte;
}

static inline bool omcu_uart1_rx_ready(void) {
  return (OMCU_UART1->status & OMCU_UART_STATUS_RX_VALID) != 0u;
}

static inline uint8_t omcu_uart1_read_byte(void) {
  return (uint8_t)OMCU_UART1->data;
}

/*
 * Request or release the portable UART1 pin-function claim.  It is a
 * feature-gated operation so an application can use one binary with a
 * smaller OpenMCU configuration without touching an undecoded MMIO page.
 * Board headers document the actual pins; a generic system does not assume
 * that UART1 has any particular package-pad mapping.
 */
static inline bool omcu_pinmux_uart1_enable(bool enable) {
  uint32_t ctrl;

  if (!omcu_hw_has_feature(OMCU_FEATURE_UART1 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  ctrl = OMCU_PINMUX->ctrl;
  if (enable) {
    ctrl |= OMCU_PINMUX_CTRL_UART1_ENABLE;
  } else {
    ctrl &= ~OMCU_PINMUX_CTRL_UART1_ENABLE;
  }
  OMCU_PINMUX->ctrl = ctrl;
  return true;
}

/* Claim or release the reviewed four-channel PWM1 pad group. */
static inline bool omcu_pinmux_pwm1_enable(bool enable) {
  uint32_t ctrl;

  if (!omcu_hw_has_feature(OMCU_FEATURE_PWM1 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  ctrl = OMCU_PINMUX->ctrl;
  if (enable) {
    ctrl |= OMCU_PINMUX_CTRL_PWM1_ENABLE;
  } else {
    ctrl &= ~OMCU_PINMUX_CTRL_PWM1_ENABLE;
  }
  OMCU_PINMUX->ctrl = ctrl;
  return true;
}

/* Claim or release the reviewed TIMER1 capture/encoder input pad pair. */
static inline bool omcu_pinmux_timer1_enable(bool enable) {
  uint32_t ctrl;

  if (!omcu_hw_has_feature(OMCU_FEATURE_TIMER1 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  ctrl = OMCU_PINMUX->ctrl;
  if (enable) {
    ctrl |= OMCU_PINMUX_CTRL_TIMER1_ENABLE;
  } else {
    ctrl &= ~OMCU_PINMUX_CTRL_TIMER1_ENABLE;
  }
  OMCU_PINMUX->ctrl = ctrl;
  return true;
}

/* Claim or release the reviewed PULSE0 low-rate input triplet. */
static inline bool omcu_pinmux_pulse0_enable(bool enable) {
  uint32_t ctrl;

  if (!omcu_hw_has_feature(OMCU_FEATURE_PULSE0 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  ctrl = OMCU_PINMUX->ctrl;
  if (enable) {
    ctrl |= OMCU_PINMUX_CTRL_PULSE0_ENABLE;
  } else {
    ctrl &= ~OMCU_PINMUX_CTRL_PULSE0_ENABLE;
  }
  OMCU_PINMUX->ctrl = ctrl;
  return true;
}

/* Claim or release the reviewed FAULT0 interlock input pad. */
static inline bool omcu_pinmux_fault0_enable(bool enable) {
  uint32_t ctrl;

  if (!omcu_hw_has_feature(OMCU_FEATURE_FAULT0 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  ctrl = OMCU_PINMUX->ctrl;
  if (enable) {
    ctrl |= OMCU_PINMUX_CTRL_FAULT0_ENABLE;
  } else {
    ctrl &= ~OMCU_PINMUX_CTRL_FAULT0_ENABLE;
  }
  OMCU_PINMUX->ctrl = ctrl;
  return true;
}

/* First-fault context remains available until the next SoC reset. */
typedef struct {
  uint32_t tick;
  uint32_t gpio_input;
  uint32_t irq_active;
  uint32_t reset_cause;
} omcu_fault0_snapshot_t;

/*
 * Configure the logic-level FAULT0 interlock without clearing a prior trip.
 * FILTER=N accepts a changed synchronized input after N+1 samples.  A latched
 * trip may be released only with omcu_fault0_try_clear() while the claimed
 * input has returned to its inactive state.
 */
static inline bool omcu_fault0_configure(
  uint8_t filter,
  uint32_t gpio_hiz_mask,
  bool active_high,
  bool enable_irq,
  bool gate_pwm0,
  bool gate_pwm1,
  bool gate_gpio
) {
  uint32_t ctrl = OMCU_FAULT_CTRL_ENABLE |
                  (active_high ? OMCU_FAULT_CTRL_ACTIVE_HIGH : 0u) |
                  (enable_irq ? OMCU_FAULT_CTRL_IRQ_ENABLE : 0u) |
                  (gate_pwm0 ? OMCU_FAULT_CTRL_GATE_PWM0 : 0u) |
                  (gate_pwm1 ? OMCU_FAULT_CTRL_GATE_PWM1 : 0u) |
                  (gate_gpio ? OMCU_FAULT_CTRL_GATE_GPIO : 0u);

  if (!omcu_hw_has_feature(OMCU_FEATURE_FAULT0)) {
    return false;
  }
  OMCU_FAULT0->ctrl = 0u;
  OMCU_FAULT0->filter = (uint32_t)filter & OMCU_FAULT_FILTER_MASK;
  OMCU_FAULT0->gpio_hiz_mask = gpio_hiz_mask;
  OMCU_FAULT0->status = OMCU_FAULT_STATUS_CLEAR_REJECTED;
  OMCU_FAULT0->ctrl = ctrl;
  return true;
}

static inline bool omcu_fault0_is_tripped(void) {
  return omcu_hw_has_feature(OMCU_FEATURE_FAULT0) &&
         (OMCU_FAULT0->status & OMCU_FAULT_STATUS_TRIPPED) != 0u;
}

/*
 * This write never overrides the hardware interlock.  It succeeds only after
 * FAULT0 is still pinmux-claimed and its filtered input is inactive.
 */
static inline bool omcu_fault0_try_clear(void) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_FAULT0)) {
    return false;
  }
  OMCU_FAULT0->clear = OMCU_FAULT_CLEAR_MAGIC;
  return (OMCU_FAULT0->status & OMCU_FAULT_STATUS_TRIPPED) == 0u;
}

static inline bool omcu_fault0_snapshot_read(omcu_fault0_snapshot_t *snapshot) {
  if (snapshot == 0 || !omcu_hw_has_feature(OMCU_FEATURE_FAULT0)) {
    return false;
  }
  snapshot->tick = OMCU_FAULT0->snapshot_tick;
  snapshot->gpio_input = OMCU_FAULT0->snapshot_gpio;
  snapshot->irq_active = OMCU_FAULT0->snapshot_irq;
  snapshot->reset_cause = OMCU_FAULT0->snapshot_reset;
  return true;
}

static inline void omcu_timer_start_periodic(
  uint16_t prescale,
  uint32_t compare
) {
  OMCU_TIMER0->ctrl = 0u;
  OMCU_TIMER0->prescale = prescale;
  OMCU_TIMER0->count = 0u;
  OMCU_TIMER0->compare = compare;
  OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
  OMCU_TIMER0->ctrl = OMCU_TIMER_CTRL_ENABLE |
                      OMCU_TIMER_CTRL_IRQ_ENABLE |
                      OMCU_TIMER_CTRL_AUTO_RELOAD;
}

/*
 * ALARM0 is a shared 32-bit timebase with four independent absolute compare
 * channels. Start it once, then arm each channel against its own deadline.
 * A periodic channel advances its compare value by period rather than resetting
 * the shared counter, so the other channels retain their phase.
 */
static inline bool omcu_alarm0_start(uint16_t prescale) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_ALARM0)) {
    return false;
  }
  OMCU_ALARM0->ctrl = 0u;
  OMCU_ALARM0->prescale = prescale;
  OMCU_ALARM0->count = 0u;
  OMCU_ALARM0->pending = OMCU_ALARM_CHANNEL_MASK;
  OMCU_ALARM0->ctrl = OMCU_ALARM_CTRL_ENABLE;
  return true;
}

static inline bool omcu_alarm0_schedule(
  uint8_t channel,
  uint32_t absolute_compare,
  uint32_t period,
  bool periodic,
  bool enable_irq
) {
  uint32_t bit;
  volatile uint32_t *compare;
  volatile uint32_t *period_register;

  if (!omcu_hw_has_feature(OMCU_FEATURE_ALARM0) ||
      channel >= OMCU_ALARM_CHANNEL_COUNT || (periodic && period == 0u)) {
    return false;
  }
  bit = UINT32_C(1) << channel;
  compare = &OMCU_ALARM0->compare0;
  period_register = &OMCU_ALARM0->period0;
  OMCU_ALARM0->channel_enable &= ~bit;
  OMCU_ALARM0->pending = bit;
  compare[channel] = absolute_compare;
  period_register[channel] = period;
  if (periodic) {
    OMCU_ALARM0->periodic |= bit;
  } else {
    OMCU_ALARM0->periodic &= ~bit;
  }
  if (enable_irq) {
    OMCU_ALARM0->irq_enable |= bit;
  } else {
    OMCU_ALARM0->irq_enable &= ~bit;
  }
  OMCU_ALARM0->channel_enable |= bit;
  return true;
}

static inline void omcu_alarm0_clear_pending(uint32_t channel_mask) {
  OMCU_ALARM0->pending = channel_mask & OMCU_ALARM_CHANNEL_MASK;
}

/*
 * PULSE0 reports a wrapping edge count and, after its second selected edge,
 * a period in SYSCTRL run-tick units. Each input is synchronized and filtered;
 * FILTER=N requires N+1 mismatched synchronized samples before a transition.
 */
static inline bool omcu_pulse0_configure(
  uint8_t channel_enable,
  uint8_t falling_mask,
  uint8_t filter,
  bool enable_irq
) {
  uint32_t channels = (uint32_t)channel_enable & OMCU_PULSE_CHANNEL_MASK;

  if (!omcu_hw_has_feature(OMCU_FEATURE_PULSE0)) {
    return false;
  }
  OMCU_PULSE0->ctrl = 0u;
  OMCU_PULSE0->filter = (uint32_t)filter;
  OMCU_PULSE0->falling = (uint32_t)falling_mask & OMCU_PULSE_CHANNEL_MASK;
  OMCU_PULSE0->clear = channels;
  OMCU_PULSE0->channel_enable = channels;
  OMCU_PULSE0->status = OMCU_PULSE_STATUS_PENDING_MASK;
  OMCU_PULSE0->ctrl = OMCU_PULSE_CTRL_ENABLE |
                      (enable_irq ? OMCU_PULSE_CTRL_IRQ_ENABLE : 0u);
  return true;
}

static inline void omcu_pulse0_clear(uint8_t channel_mask) {
  OMCU_PULSE0->clear = (uint32_t)channel_mask & OMCU_PULSE_CHANNEL_MASK;
}

static inline uint32_t omcu_pulse0_count(uint8_t channel) {
  volatile const uint32_t *count = &OMCU_PULSE0->count0;

  return (channel < OMCU_PULSE_CHANNEL_COUNT) ? count[channel] : 0u;
}

static inline uint32_t omcu_pulse0_period_ticks(uint8_t channel) {
  volatile const uint32_t *period = &OMCU_PULSE0->period0;

  return (channel < OMCU_PULSE_CHANNEL_COUNT) ? period[channel] : 0u;
}

static inline bool omcu_pulse0_period_valid(uint8_t channel) {
  return channel < OMCU_PULSE_CHANNEL_COUNT &&
         (OMCU_PULSE0->status &
          (UINT32_C(1) << (OMCU_PULSE_STATUS_VALID_SHIFT + channel))) != 0u;
}

/*
 * Configure TIMER1's 16-bit timestamp counter, filtered capture channels and/or
 * quadrature decoder. FILTER=N (0..255) accepts an input state only after N+1
 * consecutive synchronized samples disagree with the previous filtered state.
 * This is a digital glitch filter, not a substitute for an external front end
 * for signals faster than the 27 MHz system clock.
 */
static inline void omcu_timer1_configure(
  uint16_t prescale,
  uint16_t compare,
  uint8_t filter,
  uint32_t ctrl
) {
  OMCU_TIMER1->ctrl = 0u;
  OMCU_TIMER1->prescale = prescale;
  OMCU_TIMER1->count = 0u;
  OMCU_TIMER1->compare = compare;
  OMCU_TIMER1->filter = filter;
  OMCU_TIMER1->status = OMCU_TIMER1_STATUS_COMPARE |
                        OMCU_TIMER1_STATUS_CAPTURE_A |
                        OMCU_TIMER1_STATUS_CAPTURE_B |
                        OMCU_TIMER1_STATUS_ENCODER_STEP |
                        OMCU_TIMER1_STATUS_ENCODER_ILLEGAL;
  OMCU_TIMER1->ctrl = ctrl;
}

static inline void omcu_timer1_clear_status(uint32_t mask) {
  OMCU_TIMER1->status = mask &
    (OMCU_TIMER1_STATUS_COMPARE |
     OMCU_TIMER1_STATUS_CAPTURE_A |
     OMCU_TIMER1_STATUS_CAPTURE_B |
     OMCU_TIMER1_STATUS_ENCODER_STEP |
     OMCU_TIMER1_STATUS_ENCODER_ILLEGAL);
}

static inline int32_t omcu_timer1_encoder_position(void) {
  return (int32_t)OMCU_TIMER1->encoder;
}

static inline void omcu_timer1_set_encoder_position(int16_t position) {
  OMCU_TIMER1->encoder = (uint32_t)(int32_t)position;
}

static inline void omcu_spi0_init(uint16_t clkdiv, bool enable_done_irq) {
  OMCU_SPI0->ctrl = 0u;
  OMCU_SPI0->clkdiv = clkdiv;
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  OMCU_SPI0->ctrl = OMCU_SPI_CTRL_ENABLE |
                     (enable_done_irq ? OMCU_SPI_CTRL_IRQ_ENABLE : 0u);
}

static inline bool omcu_spi0_transfer(uint8_t tx, uint8_t *rx) {
  uint32_t status;

  if ((OMCU_SPI0->ctrl & OMCU_SPI_CTRL_ENABLE) == 0u) {
    return false;
  }
  while ((OMCU_SPI0->status & OMCU_SPI_STATUS_BUSY) != 0u) {
  }
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  OMCU_SPI0->data = tx;
  OMCU_SPI0->start = 1u;
  do {
    status = OMCU_SPI0->status;
  } while ((status & OMCU_SPI_STATUS_BUSY) != 0u);
  if ((status & OMCU_SPI_STATUS_DONE) == 0u) {
    return false;
  }
  if (rx != 0) {
    *rx = (uint8_t)OMCU_SPI0->data;
  }
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  return true;
}

/*
 * Keep CS asserted across separately started SPI bytes.  This is required by
 * framed devices such as W5500 and MCP3008.  Set it before the first START,
 * wait for the final transfer to finish, then clear it to release CS.  The
 * default remains one automatic CS assertion per byte for compatibility with
 * the original OpenMCU SPI API.
 */
static inline void omcu_spi0_set_cs_hold(bool hold) {
  uint32_t ctrl = OMCU_SPI0->ctrl;

  if (hold) {
    ctrl |= OMCU_SPI_CTRL_CS_HOLD;
  } else {
    ctrl &= ~OMCU_SPI_CTRL_CS_HOLD;
  }
  OMCU_SPI0->ctrl = ctrl;
}

static inline bool omcu_spi0_cs_active(void) {
  return (OMCU_SPI0->status & OMCU_SPI_STATUS_CS_ACTIVE) != 0u;
}

static inline void omcu_i2c0_init(uint16_t clkdiv, bool enable_done_irq) {
  OMCU_I2C0->ctrl = 0u;
  OMCU_I2C0->clkdiv = clkdiv;
  OMCU_I2C0->status = OMCU_I2C_STATUS_DONE |
                       OMCU_I2C_STATUS_ACK_ERROR |
                       OMCU_I2C_STATUS_COMMAND_ERROR;
  OMCU_I2C0->ctrl = OMCU_I2C_CTRL_ENABLE |
                    (enable_done_irq ? OMCU_I2C_CTRL_IRQ_ENABLE : 0u);
}

static inline bool omcu_i2c0_command(uint32_t command) {
  uint32_t status;

  if ((OMCU_I2C0->ctrl & OMCU_I2C_CTRL_ENABLE) == 0u) {
    return false;
  }
  while ((OMCU_I2C0->status & OMCU_I2C_STATUS_BUSY) != 0u) {
  }
  OMCU_I2C0->status = OMCU_I2C_STATUS_DONE |
                       OMCU_I2C_STATUS_ACK_ERROR |
                       OMCU_I2C_STATUS_COMMAND_ERROR;
  OMCU_I2C0->cmd = command;
  do {
    status = OMCU_I2C0->status;
  } while ((status & OMCU_I2C_STATUS_BUSY) != 0u);
  return (status & (OMCU_I2C_STATUS_DONE |
                    OMCU_I2C_STATUS_ACK_ERROR |
                    OMCU_I2C_STATUS_COMMAND_ERROR)) == OMCU_I2C_STATUS_DONE;
}

static inline bool omcu_i2c0_start(void) {
  return omcu_i2c0_command(OMCU_I2C_CMD_START);
}

static inline bool omcu_i2c0_stop(void) {
  return omcu_i2c0_command(OMCU_I2C_CMD_STOP);
}

static inline bool omcu_i2c0_write_byte(uint8_t byte) {
  OMCU_I2C0->data = byte;
  return omcu_i2c0_command(OMCU_I2C_CMD_WRITE);
}

// Set acknowledge=false for the final byte in a target-to-controller read.
static inline bool omcu_i2c0_read_byte(uint8_t *byte, bool acknowledge) {
  if (!omcu_i2c0_command(
        acknowledge ? OMCU_I2C_CMD_READ_ACK : OMCU_I2C_CMD_READ_NACK)) {
    return false;
  }
  if (byte != 0) {
    *byte = (uint8_t)OMCU_I2C0->data;
  }
  return true;
}

static inline void omcu_wdt0_start(
  uint32_t timeout,
  bool request_reset,
  bool enable_expiry_irq
) {
  OMCU_WDT0->ctrl = 0u;
  OMCU_WDT0->timeout = timeout;
  OMCU_WDT0->status = OMCU_WDT_STATUS_EXPIRED;
  OMCU_WDT0->feed = OMCU_WDT_FEED_MAGIC;
  OMCU_WDT0->ctrl = OMCU_WDT_CTRL_ENABLE |
                    (request_reset ? OMCU_WDT_CTRL_RESET_ENABLE : 0u) |
                    (enable_expiry_irq ? OMCU_WDT_CTRL_IRQ_ENABLE : 0u);
}

static inline void omcu_wdt0_feed(void) {
  OMCU_WDT0->feed = OMCU_WDT_FEED_MAGIC;
}

/*
 * Start the optional supervised watchdog profile. PRETIMEOUT and WINDOW_MIN
 * are counts in the 27 MHz system clock domain. A nonzero heartbeat mask
 * requires every selected task bit to be kicked during each feed epoch.
 */
static inline bool omcu_wdt0_start_supervisor(
  uint32_t timeout,
  uint32_t pretimeout,
  uint32_t window_min,
  uint8_t heartbeat_required,
  bool request_reset,
  bool enable_expiry_irq,
  bool enable_pretimeout_irq
) {
  uint32_t ctrl = OMCU_WDT_CTRL_ENABLE |
                  (request_reset ? OMCU_WDT_CTRL_RESET_ENABLE : 0u) |
                  (enable_expiry_irq ? OMCU_WDT_CTRL_IRQ_ENABLE : 0u) |
                  ((pretimeout != 0u && enable_pretimeout_irq) ?
                    OMCU_WDT_CTRL_PRETIMEOUT_IRQ_ENABLE : 0u) |
                  ((window_min != 0u) ? OMCU_WDT_CTRL_WINDOW_ENABLE : 0u) |
                  ((heartbeat_required != 0u) ?
                    OMCU_WDT_CTRL_HEARTBEAT_ENABLE : 0u);

  if (!omcu_hw_has_feature(OMCU_FEATURE_WDT0 |
                           OMCU_FEATURE_WDT_SUPERVISOR) ||
      timeout == 0u ||
      (pretimeout != 0u && pretimeout >= timeout) ||
      (window_min != 0u && window_min >= timeout)) {
    return false;
  }
  OMCU_WDT0->ctrl = 0u;
  OMCU_WDT0->timeout = timeout;
  OMCU_WDT0->pretimeout = pretimeout;
  OMCU_WDT0->window_min = window_min;
  OMCU_WDT0->heartbeat_required =
    (uint32_t)heartbeat_required & OMCU_WDT_HEARTBEAT_MASK;
  OMCU_WDT0->status = OMCU_WDT_STATUS_EXPIRED |
                      OMCU_WDT_STATUS_PRETIMEOUT |
                      OMCU_WDT_STATUS_WINDOW_VIOLATION |
                      OMCU_WDT_STATUS_HEARTBEAT_MISSING |
                      OMCU_WDT_STATUS_FEED_REJECTED;
  OMCU_WDT0->ctrl = ctrl;
  return true;
}

/* Record progress from one supervised task during the current WDT epoch. */
static inline bool omcu_wdt0_heartbeat_kick(uint8_t task_mask) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_WDT0 |
                           OMCU_FEATURE_WDT_SUPERVISOR) ||
      task_mask == 0u) {
    return false;
  }
  OMCU_WDT0->heartbeat_kick =
    (uint32_t)task_mask & OMCU_WDT_HEARTBEAT_MASK;
  return true;
}

static inline void omcu_wdt0_clear_supervisor_status(uint32_t status_mask) {
  OMCU_WDT0->status = status_mask &
                       (OMCU_WDT_STATUS_EXPIRED |
                        OMCU_WDT_STATUS_PRETIMEOUT |
                        OMCU_WDT_STATUS_WINDOW_VIOLATION |
                        OMCU_WDT_STATUS_HEARTBEAT_MISSING |
                        OMCU_WDT_STATUS_FEED_REJECTED);
}

static inline void omcu_wdt0_stop(void) {
  OMCU_WDT0->ctrl = 0u;
}

static inline void omcu_pwm0_configure(
  uint16_t prescale,
  uint32_t period,
  uint32_t duty,
  bool invert
) {
  OMCU_PWM0->ctrl = 0u;
  OMCU_PWM0->prescale = prescale;
  OMCU_PWM0->period = period;
  OMCU_PWM0->duty = duty;
  OMCU_PWM0->ctrl = OMCU_PWM_CTRL_ENABLE |
                    (invert ? OMCU_PWM_CTRL_INVERT : 0u);
}

/*
 * Configure four PWM1 channels that share one prescaler, 16-bit period and phase.
 * Bit n of invert_mask controls channel n.  The caller may update DUTY0..3
 * directly between cycles when a synchronized multi-register update is not
 * required by the attached power stage.
 */
static inline void omcu_pwm1_configure(
  uint16_t prescale,
  uint16_t period,
  uint16_t duty0,
  uint16_t duty1,
  uint16_t duty2,
  uint16_t duty3,
  uint8_t invert_mask
) {
  OMCU_PWM1->ctrl = 0u;
  OMCU_PWM1->prescale = prescale;
  OMCU_PWM1->period = period;
  OMCU_PWM1->duty0 = duty0;
  OMCU_PWM1->duty1 = duty1;
  OMCU_PWM1->duty2 = duty2;
  OMCU_PWM1->duty3 = duty3;
  OMCU_PWM1->ctrl = OMCU_PWM1_CTRL_ENABLE |
                    (((uint32_t)invert_mask << OMCU_PWM1_CTRL_INVERT_SHIFT) &
                     OMCU_PWM1_CTRL_INVERT_MASK);
}

#endif  /* OMCU_H_ */
