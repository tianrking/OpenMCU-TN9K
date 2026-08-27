#include "omcu_tn9k.h"

enum {
  UART1_ECHO_QUEUE_BYTES = 256u,
};

static uint8_t echo_queue[UART1_ECHO_QUEUE_BYTES];

/*
 * Stand-alone HIL image for the optional Tang UART1 route.  Keep UART0 free
 * for the Bootloader/download path and connect a 3.3 V USB-TTL adapter to
 * J5.18 (FPGA TX -> adapter RX) and J5.19 (FPGA RX <- adapter TX).
 *
 * RX and TX are serviced independently.  Waiting synchronously for a whole
 * transmitted frame after every received byte leaves the single-byte RX
 * holding register vulnerable to overrun under a continuous USB-UART burst.
 * This small software queue lets the CPU drain RX while the previous byte is
 * still leaving the TX shift register.
 */
int main(void) {
  const uint32_t required = OMCU_FEATURE_UART1 | OMCU_FEATURE_PINMUX;
  uint8_t head = 0u;
  uint8_t tail = 0u;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required) ||
      !omcu_tn9k_uart1_init(omcu_tn9k_uart_bauddiv(115200u), false)) {
    for (;;) {
    }
  }

  for (;;) {
    const uint8_t next_head = (uint8_t)(head + 1u);

    if (omcu_uart1_rx_ready() && next_head != tail) {
      echo_queue[head] = omcu_uart1_read_byte();
      head = next_head;
    }
    if (tail != head && omcu_uart1_tx_ready()) {
      OMCU_UART1->data = echo_queue[tail];
      tail = (uint8_t)(tail + 1u);
    }
  }
}
