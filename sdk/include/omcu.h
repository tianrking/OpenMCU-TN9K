#ifndef OMCU_H_
#define OMCU_H_

/*
 * OpenMCU public v0 device header.
 *
 * This header is intentionally compiler-light: it works with a normal
 * riscv32-unknown-elf C compiler and does not depend on a vendor SDK.
 */

#include "omcu_regs.h"

#include <stdbool.h>

enum {
  OMCU_UART_CTRL_TX_ENABLE = 1u << 0,
  OMCU_UART_CTRL_RX_ENABLE = 1u << 1,
  OMCU_UART_CTRL_RX_IRQ_ENABLE = 1u << 2,
  OMCU_UART_STATUS_TX_READY = 1u << 0,
  OMCU_UART_STATUS_RX_VALID = 1u << 1,
  OMCU_UART_STATUS_RX_OVERRUN = 1u << 2,
  OMCU_UART_STATUS_RX_FRAMING_ERROR = 1u << 3,
};

static inline bool omcu_hw_abi_is_compatible(uint16_t expected_major) {
  return OMCU_SYSCTRL->chip_id == OMCU_CHIP_ID &&
         (uint16_t)(OMCU_SYSCTRL->abi >> OMCU_SYSCTRL_ABI_MAJOR_SHIFT) ==
           expected_major;
}

static inline void omcu_gpio_enable_output(uint32_t mask) {
  OMCU_GPIO0->oe_set = mask;
}

static inline void omcu_gpio_disable_output(uint32_t mask) {
  OMCU_GPIO0->oe_clr = mask;
}

static inline void omcu_gpio_set(uint32_t mask) {
  OMCU_GPIO0->out_set = mask;
}

static inline void omcu_gpio_clear(uint32_t mask) {
  OMCU_GPIO0->out_clr = mask;
}

static inline void omcu_gpio_toggle(uint32_t mask) {
  OMCU_GPIO0->out_xor = mask;
}

static inline void omcu_uart0_init(uint16_t bauddiv, bool enable_rx_irq) {
  OMCU_UART0->ctrl = 0u;
  OMCU_UART0->bauddiv = bauddiv;
  OMCU_UART0->status = OMCU_UART_STATUS_RX_OVERRUN |
                       OMCU_UART_STATUS_RX_FRAMING_ERROR;
  OMCU_UART0->ctrl = OMCU_UART_CTRL_TX_ENABLE |
                    OMCU_UART_CTRL_RX_ENABLE |
                    (enable_rx_irq ? OMCU_UART_CTRL_RX_IRQ_ENABLE : 0u);
}

static inline bool omcu_uart0_tx_ready(void) {
  return (OMCU_UART0->status & OMCU_UART_STATUS_TX_READY) != 0u;
}

static inline void omcu_uart0_write_byte(uint8_t byte) {
  while (!omcu_uart0_tx_ready()) {
  }
  OMCU_UART0->data = byte;
}

static inline bool omcu_uart0_rx_ready(void) {
  return (OMCU_UART0->status & OMCU_UART_STATUS_RX_VALID) != 0u;
}

static inline uint8_t omcu_uart0_read_byte(void) {
  return (uint8_t)OMCU_UART0->data;
}

static inline void omcu_timer_start_periodic(
  uint16_t prescale,
  uint32_t compare
) {
  OMCU_TIMER0->ctrl = 0u;
  OMCU_TIMER0->prescale = prescale;
  OMCU_TIMER0->count = 0u;
  OMCU_TIMER0->compare = compare;
  OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
  OMCU_TIMER0->ctrl = OMCU_TIMER_CTRL_ENABLE |
                      OMCU_TIMER_CTRL_IRQ_ENABLE |
                      OMCU_TIMER_CTRL_AUTO_RELOAD;
}

#endif  /* OMCU_H_ */
