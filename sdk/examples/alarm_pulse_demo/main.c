#include "omcu_tn9k.h"

/*
 * One independently programmable application showing both resource-efficient
 * timing and a low-rate sensor input. ALARM0 channel 0 toggles LED0 twice per
 * second from a 1 kHz TIMER0-shared timebase; PULSE0 measures rising edges on its
 * selected GPIO0/J5.8 input with a small digital filter.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_ALARM0 |
                            OMCU_FEATURE_PULSE0 |
                            OMCU_FEATURE_PINMUX |
                            OMCU_FEATURE_GPIO_EXPANSION;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_alarm0_start(26999u) ||
      !omcu_alarm0_schedule_after(0u, 500u, 500u, true, false) ||
      !omcu_tn9k_pulse0_configure(0u, false, 4u, false)) {
    for (;;) {
    }
  }

  omcu_gpio_enable_output(OMCU_TN9K_LED0 | OMCU_TN9K_LED1);
  omcu_gpio_clear(OMCU_TN9K_LED0 | OMCU_TN9K_LED1);

  for (;;) {
    if ((OMCU_ALARM0->pending & 1u) != 0u) {
      omcu_alarm0_clear_pending(1u);
      omcu_gpio_toggle(OMCU_TN9K_LED0);
    }
    if ((OMCU_PULSE0->status & 1u) != 0u) {
      OMCU_PULSE0->status = 1u;
      /* LED1 proves a filtered sensor edge reached the MCU. */
      omcu_gpio_toggle(OMCU_TN9K_LED1);
    }
  }
}
