#include "omcu_tn9k.h"

#include <stdint.h>

/*
 * A minimal independently programmable application that deliberately returns
 * a product MCU to its UART0 Bootloader.  It is a recovery/update-flow demo,
 * not a normal application startup template: after the request is accepted,
 * the SoC resets and the Bootloader remains available until the host sends its
 * normal BOOT command.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_DIAGNOSTICS |
                            OMCU_FEATURE_USER_FLASH;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    for (;;) {
    }
  }

  omcu_gpio_enable_output(OMCU_TN9K_LED0);
  omcu_gpio_set(OMCU_TN9K_LED0);
  (void)omcu_tn9k_request_bootloader();
  for (;;) {
  }
}
