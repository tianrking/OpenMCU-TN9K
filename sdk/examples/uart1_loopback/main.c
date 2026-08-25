#include "omcu_tn9k.h"

/*
 * Stand-alone HIL image for the optional Tang UART1 route.  Keep UART0 free
 * for the Bootloader/download path and connect a 3.3 V USB-TTL adapter to
 * J5.18 (FPGA TX -> adapter RX) and J5.19 (FPGA RX <- adapter TX).
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_UART1 | OMCU_FEATURE_PINMUX;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_uart1_init(omcu_tn9k_uart_bauddiv(115200u), false)) {
    for (;;) {
    }
  }

  for (;;) {
    if (omcu_uart1_rx_ready()) {
      omcu_uart1_write_byte(omcu_uart1_read_byte());
    }
  }
}
