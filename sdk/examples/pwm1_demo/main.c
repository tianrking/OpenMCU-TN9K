#include "omcu_tn9k.h"

/*
 * Four-channel PWM1 HIL image.  UART0 stays available for the bootloader;
 * observe only the explicitly selected J5.12..15 GPIO4..7 PWM pad group.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_PWM1 | OMCU_FEATURE_PINMUX;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_pwm1_configure(
        26u, 999u, 250u, 500u, 750u, 1000u, 0u)) {
    for (;;) {
    }
  }

  for (;;) {
    /* Keep a stable four-phase-duty waveform for scope/logic-analyzer HIL. */
  }
}
