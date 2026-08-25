#include "omcu_tn9k.h"

#include <stdint.h>

/*
 * ROM-only regression fixture for the platform reset path.  The first boot
 * asks for the product Bootloader; the next reset sees SOFTWARE and stays in
 * this image so the RTL test can inspect the retained diagnostics.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_DIAGNOSTICS |
                            OMCU_FEATURE_USER_FLASH;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    for (;;) {
    }
  }

  if ((omcu_sysctrl_reset_cause() & OMCU_RESET_CAUSE_SOFTWARE) == 0u) {
    (void)omcu_tn9k_request_bootloader();
    for (;;) {
    }
  }

  omcu_gpio_enable_output(OMCU_TN9K_LED0);
  omcu_gpio_set(OMCU_TN9K_LED0);
  for (;;) {
  }
}
