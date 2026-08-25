#include "omcu_tn9k.h"

/*
 * Customer-style independent image for a low-rate quadrature encoder/input
 * capture experiment.  Start with FILTER=4 and tune it from measured switch
 * or encoder bounce; it is not a high-speed asynchronous counter.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_TIMER1 | OMCU_FEATURE_PINMUX;
  const uint32_t ctrl = OMCU_TIMER1_CTRL_ENABLE |
                        OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE |
                        OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE |
                        OMCU_TIMER1_CTRL_QUADRATURE_ENABLE;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_timer1_configure(0u, UINT16_MAX, 4u, ctrl)) {
    for (;;) {
    }
  }

  for (;;) {
    if ((OMCU_TIMER1->status & OMCU_TIMER1_STATUS_ENCODER_ILLEGAL) != 0u) {
      omcu_timer1_clear_status(OMCU_TIMER1_STATUS_ENCODER_ILLEGAL);
      /* Product code can record or act on an invalid Gray transition here. */
    }
  }
}
