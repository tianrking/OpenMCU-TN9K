#include "omcu.h"
#include "omcu_tn9k.h"

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

/* 用于让输出可见的演示间隔，不是精确时基。 */
static void delay_cycles(volatile uint32_t cycles) {
  while (cycles-- != 0u) {
    __asm__ volatile ("nop");
  }
}

int main(void) {
  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(OMCU_FEATURE_UART0 | OMCU_FEATURE_USER_FLASH)) {
    for (;;) {
    }
  }

  omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);

  for (;;) {
    uart_write_string("Hello, OpenMCU-TN9K!\r\n");
    delay_cycles(2700000u);
  }
}
