#ifndef OMCU_TN9K_H_
#define OMCU_TN9K_H_

/*
 * Tang Nano 9K board support definitions for the public OpenMCU SDK.
 *
 * This header describes the fixed board wrapper in
 * rtl/platform/tangnano9k/omcu_tn9k_bringup_top.sv.  It contains logical MCU
 * GPIO numbers, never raw FPGA package pin numbers; physical pins belong to
 * the reviewed CST and the board documentation.
 */

#include "omcu.h"

#define OMCU_TN9K_SYSCLK_HZ       UINT32_C(27000000)
#define OMCU_TN9K_LED0            (UINT32_C(1) << 0)
#define OMCU_TN9K_LED1            (UINT32_C(1) << 1)
#define OMCU_TN9K_LED2            (UINT32_C(1) << 2)
#define OMCU_TN9K_LED3            (UINT32_C(1) << 3)
#define OMCU_TN9K_LED4            (UINT32_C(1) << 4)
#define OMCU_TN9K_LED5            (UINT32_C(1) << 5)
#define OMCU_TN9K_GPIO0           (UINT32_C(1) << 6)
#define OMCU_TN9K_GPIO1           (UINT32_C(1) << 7)
#define OMCU_TN9K_GPIO2           (UINT32_C(1) << 8)
#define OMCU_TN9K_GPIO3           (UINT32_C(1) << 9)
#define OMCU_TN9K_GPIO4           (UINT32_C(1) << 10)
#define OMCU_TN9K_GPIO5           (UINT32_C(1) << 11)
#define OMCU_TN9K_GPIO6           (UINT32_C(1) << 12)
#define OMCU_TN9K_GPIO7           (UINT32_C(1) << 13)
#define OMCU_TN9K_GPIO8           (UINT32_C(1) << 14)
#define OMCU_TN9K_GPIO9           (UINT32_C(1) << 15)
#define OMCU_TN9K_GPIO10          (UINT32_C(1) << 16)
#define OMCU_TN9K_GPIO11          (UINT32_C(1) << 17)

/* Rounded divider for the UART0/UART1 convention: clocks-per-bit minus one. */
static inline uint16_t omcu_tn9k_uart_bauddiv(uint32_t baud) {
  uint32_t clocks_per_bit;

  if (baud == 0u) {
    return 0u;
  }
  clocks_per_bit = (OMCU_TN9K_SYSCLK_HZ + (baud / 2u)) / baud;
  return (uint16_t)((clocks_per_bit == 0u) ? 0u : clocks_per_bit - 1u);
}

/*
 * Tang Nano 9K routes UART1 TX to GPIO10 / J5.18 and UART1 RX to GPIO11 /
 * J5.19 only after this call.  Before it, both pads remain ordinary GPIO.
 * The two pins share the RGB-LCD header group, so do not enable this route
 * while an RGB LCD uses that interface.
 */
static inline bool omcu_tn9k_uart1_init(
  uint16_t bauddiv,
  bool enable_rx_irq
) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_UART1 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  omcu_uart1_init(bauddiv, enable_rx_irq);
  return omcu_pinmux_uart1_enable(true);
}

static inline bool omcu_tn9k_uart1_release_pins(void) {
  return omcu_pinmux_uart1_enable(false);
}

/*
 * Tang PWM1 channel 0..3 maps to GPIO4..7 / J5.12..15 after this call.  All
 * four routes are in the RGB-LCD-shared group and must not be used with that
 * interface or connected directly to a motor/power gate.
 */
static inline bool omcu_tn9k_pwm1_configure(
  uint16_t prescale,
  uint16_t period,
  uint16_t duty0,
  uint16_t duty1,
  uint16_t duty2,
  uint16_t duty3,
  uint8_t invert_mask
) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_PWM1 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  omcu_pwm1_configure(
    prescale, period, duty0, duty1, duty2, duty3, invert_mask
  );
  return omcu_pinmux_pwm1_enable(true);
}

static inline bool omcu_tn9k_pwm1_release_pins(void) {
  return omcu_pinmux_pwm1_enable(false);
}

/*
 * Tang TIMER1 input A/B maps to GPIO8/9 / J5.16/17 after this call.  Pinmux
 * releases both FPGA outputs so an encoder or external input can own the
 * wires; GPIO reads may still observe them but must not enable their OE bits.
 */
static inline bool omcu_tn9k_timer1_configure(
  uint16_t prescale,
  uint16_t compare,
  uint8_t filter,
  uint32_t ctrl
) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_TIMER1 | OMCU_FEATURE_PINMUX)) {
    return false;
  }
  omcu_timer1_configure(prescale, compare, filter, ctrl);
  return omcu_pinmux_timer1_enable(true);
}

static inline bool omcu_tn9k_timer1_release_pins(void) {
  return omcu_pinmux_timer1_enable(false);
}

/*
 * PULSE0 channel 0..2 maps to GPIO0..2 / J5.8..10. The route is input-only:
 * its pinmux claim releases all three FPGA output drivers before an external
 * Hall, flow or low-rate pulse sensor is connected. It is not a high-speed
 * asynchronous counter or an electrical input-protection circuit.
 */
static inline bool omcu_tn9k_pulse0_configure(
  uint8_t channel_enable,
  uint8_t falling_mask,
  uint8_t filter,
  bool enable_irq
) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_PULSE0 | OMCU_FEATURE_PINMUX) ||
      !omcu_pulse0_configure(channel_enable, falling_mask, filter, enable_irq)) {
    return false;
  }
  return omcu_pinmux_pulse0_enable(true);
}

static inline bool omcu_tn9k_pulse0_release_pins(void) {
  return omcu_pinmux_pulse0_enable(false);
}

/*
 * Request the product MCU's UART0 Bootloader without rebuilding the FPGA
 * configuration.  This is unavailable on a bring-up-only bitstream: it needs
 * both the retained diagnostics/reset sequencer and the User Flash product
 * memory contract.  On success, the caller should immediately stop normal
 * work because the SoC will reset into the Bootloader.
 */
static inline bool omcu_tn9k_request_bootloader(void) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_DIAGNOSTICS |
                           OMCU_FEATURE_USER_FLASH)) {
    return false;
  }
  return omcu_request_bootloader();
}

#endif  /* OMCU_TN9K_H_ */
