#include "omcu_tn9k.h"

/* RTL/Tang-wrapper input-capture and quadrature regression image. */
int main(void) {
  const uint32_t required = OMCU_FEATURE_TIMER1 | OMCU_FEATURE_PINMUX;
  const uint32_t ctrl = OMCU_TIMER1_CTRL_ENABLE |
                        OMCU_TIMER1_CTRL_AUTO_RELOAD |
                        OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE |
                        OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE |
                        OMCU_TIMER1_CTRL_QUADRATURE_ENABLE;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_timer1_configure(0u, UINT32_MAX, 0u, ctrl)) {
    for (;;) {
    }
  }

  for (;;) {
  }
}
