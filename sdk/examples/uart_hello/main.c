#include "omcu.h"

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

int main(void) {
  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR)) {
    for (;;) {
    }
  }

  /* 27 MHz / 234 clocks per bit is approximately 115200 baud. */
  omcu_uart0_init(233u, false);
  uart_write_string("OpenMCU-TN9K UART0 online\r\n");

  for (;;) {
  }
}
