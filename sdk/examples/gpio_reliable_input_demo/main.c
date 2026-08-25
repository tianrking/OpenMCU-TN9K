#include "omcu_tn9k.h"

/*
 * Customer-style input-conditioning and first-event-diagnosis demo.
 * GPIO0/J5.8 is released as a slow input; LED0 reflects the level captured at
 * the first filtered transition.  It deliberately polls instead of taking the
 * shared GPIO0 IRQ so the same image also demonstrates the no-ISR workflow.
 */
int main(void) {
  const uint32_t input = OMCU_TN9K_GPIO0;
  const uint32_t required = OMCU_FEATURE_GPIO0 |
                            OMCU_FEATURE_GPIO_EXPANSION |
                            OMCU_FEATURE_GPIO_RELIABILITY;
  omcu_gpio_snapshot_t snapshot;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_gpio_configure_filter(8u) ||
      !omcu_gpio_snapshot_arm(input, input, false, false)) {
    for (;;) {
    }
  }

  omcu_gpio_disable_output(input);
  omcu_gpio_enable_output(OMCU_TN9K_LED0);
  omcu_gpio_clear(OMCU_TN9K_LED0);

  for (;;) {
    if (omcu_gpio_snapshot_read(&snapshot)) {
      if ((snapshot.input_level & input) != 0u) {
        omcu_gpio_set(OMCU_TN9K_LED0);
      } else {
        omcu_gpio_clear(OMCU_TN9K_LED0);
      }
      /* Keep the first state readable until this deliberate acknowledgement. */
      omcu_gpio_snapshot_clear();
    }
  }
}
