#include "omcu.h"
#include "omcu_image.h"
#include "omcu_tn9k.h"

static void delay_cycles(volatile uint32_t cycles) {
  while (cycles-- != 0u) {
    __asm__ volatile ("nop");
  }
}

int main(void) {
  if (!omcu_hw_has_feature(OMCU_FEATURE_USER_FLASH)) {
    for (;;) {
    }
  }

  omcu_gpio_enable_output(OMCU_TN9K_LED0);
  for (;;) {
    omcu_gpio_toggle(OMCU_TN9K_LED0);
    delay_cycles(250000u);
  }
}
