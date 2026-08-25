#include "omcu_tn9k.h"

/*
 * Customer-style safety-supervision skeleton. FAULT0 is GPIO3/J5.11, active
 * high in this example, and must be held at a defined inactive level by the
 * external circuit before programming the application. A latched fault stops
 * watchdog feeds; the hardware gate already holds selected PWM/GPIO outputs
 * safe before the reset request is emitted.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_FAULT0 |
                            OMCU_FEATURE_WDT0 |
                            OMCU_FEATURE_WDT_SUPERVISOR |
                            OMCU_FEATURE_PINMUX |
                            OMCU_FEATURE_GPIO_EXPANSION;
  const uint32_t timeout = OMCU_TN9K_SYSCLK_HZ;
  const uint32_t pretimeout = OMCU_TN9K_SYSCLK_HZ / 2u;
  const uint32_t min_feed = OMCU_TN9K_SYSCLK_HZ / 100u;
  const uint32_t safe_hiz = OMCU_TN9K_GPIO0 | OMCU_TN9K_GPIO1;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_fault0_configure(
        8u, safe_hiz, true, true, true, true, true) ||
      !omcu_wdt0_start_supervisor(
        timeout, pretimeout, min_feed, 0x03u, true, false, false)) {
    for (;;) {
    }
  }

  omcu_gpio_enable_output(OMCU_TN9K_LED0 | OMCU_TN9K_LED1);
  omcu_gpio_clear(OMCU_TN9K_LED0 | OMCU_TN9K_LED1);

  for (;;) {
    /* Replace these two points with successful completion of independent jobs. */
    (void)omcu_wdt0_heartbeat_kick(0x01u);
    (void)omcu_wdt0_heartbeat_kick(0x02u);

    while (OMCU_WDT0->count < min_feed) {
    }

    if (omcu_fault0_is_tripped()) {
      omcu_gpio_set(OMCU_TN9K_LED1);
      /* Do not clear FAULT0 automatically and do not feed the watchdog. */
      for (;;) {
      }
    }

    omcu_wdt0_feed();
    omcu_gpio_toggle(OMCU_TN9K_LED0);
  }
}
