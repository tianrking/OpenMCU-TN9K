#include "omcu_tn9k.h"

/* RTL/Tang-wrapper regression image; customers should use omcu_pwm1_demo. */
int main(void) {
  const uint32_t required = OMCU_FEATURE_PWM1 | OMCU_FEATURE_PINMUX;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_pwm1_configure(0u, 7u, 1u, 2u, 3u, 4u, 0u)) {
    for (;;) {
    }
  }

  for (;;) {
  }
}
