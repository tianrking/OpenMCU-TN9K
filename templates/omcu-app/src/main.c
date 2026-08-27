#include "omcu_tn9k.h"

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

static void delay_cycles(volatile uint32_t cycles) {
  while (cycles-- != 0u) {
    __asm__ volatile ("nop");
  }
}

int main(void) {
  const uint32_t required = OMCU_FEATURE_GPIO0 |
                            OMCU_FEATURE_UART0 |
                            OMCU_FEATURE_USER_FLASH;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    for (;;) {
    }
  }

  omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);
  omcu_gpio_enable_output(OMCU_TN9K_LED0);

  for (;;) {
    uart_write_string("my_omcu_app is running\r\n");
    omcu_gpio_toggle(OMCU_TN9K_LED0);
    delay_cycles(2700000u);
  }
}
