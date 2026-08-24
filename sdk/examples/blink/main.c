#include "omcu.h"

/*
 * Board definitions own the LED polarity and physical pin assignment. The
 * portable example only uses GPIO bit 0 as its logical LED endpoint.
 */
#define OMCU_BOARD_LED0 (1u << 0)

static void delay_cycles(volatile uint32_t cycles) {
  while (cycles-- != 0u) {
    __asm__ volatile ("nop");
  }
}

int main(void) {
  omcu_gpio_enable_output(OMCU_BOARD_LED0);

  for (;;) {
    omcu_gpio_toggle(OMCU_BOARD_LED0);
    delay_cycles(250000u);
  }
}
