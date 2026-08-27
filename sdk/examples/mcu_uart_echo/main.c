#include "omcu.h"
#include "omcu_tn9k.h"

#include <stdint.h>

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

int main(void) {
  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(OMCU_FEATURE_UART0 | OMCU_FEATURE_USER_FLASH)) {
    for (;;) {
    }
  }

  omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);
  while (omcu_uart0_rx_ready()) {
    (void)omcu_uart0_read_byte();
  }
  uart_write_string("OMCU_UART0_ECHO_READY\r\n");

  for (;;) {
    if (omcu_uart0_rx_ready()) {
      omcu_uart0_write_byte(omcu_uart0_read_byte());
    }
  }
}
