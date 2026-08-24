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

static inline bool omcu_hw_has_feature(uint32_t feature) {
  return (OMCU_SYSCTRL->features & feature) == feature;
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

static inline void omcu_spi0_init(uint16_t clkdiv, bool enable_done_irq) {
  OMCU_SPI0->ctrl = 0u;
  OMCU_SPI0->clkdiv = clkdiv;
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  OMCU_SPI0->ctrl = OMCU_SPI_CTRL_ENABLE |
                     (enable_done_irq ? OMCU_SPI_CTRL_IRQ_ENABLE : 0u);
}

static inline bool omcu_spi0_transfer(uint8_t tx, uint8_t *rx) {
  uint32_t status;

  if ((OMCU_SPI0->ctrl & OMCU_SPI_CTRL_ENABLE) == 0u) {
    return false;
  }
  while ((OMCU_SPI0->status & OMCU_SPI_STATUS_BUSY) != 0u) {
  }
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  OMCU_SPI0->data = tx;
  OMCU_SPI0->start = 1u;
  do {
    status = OMCU_SPI0->status;
  } while ((status & OMCU_SPI_STATUS_BUSY) != 0u);
  if ((status & OMCU_SPI_STATUS_DONE) == 0u) {
    return false;
  }
  if (rx != 0) {
    *rx = (uint8_t)OMCU_SPI0->data;
  }
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  return true;
}

static inline void omcu_i2c0_init(uint16_t clkdiv, bool enable_done_irq) {
  OMCU_I2C0->ctrl = 0u;
  OMCU_I2C0->clkdiv = clkdiv;
  OMCU_I2C0->status = OMCU_I2C_STATUS_DONE |
                       OMCU_I2C_STATUS_ACK_ERROR |
                       OMCU_I2C_STATUS_COMMAND_ERROR;
  OMCU_I2C0->ctrl = OMCU_I2C_CTRL_ENABLE |
                    (enable_done_irq ? OMCU_I2C_CTRL_IRQ_ENABLE : 0u);
}

static inline bool omcu_i2c0_command(uint32_t command) {
  uint32_t status;

  if ((OMCU_I2C0->ctrl & OMCU_I2C_CTRL_ENABLE) == 0u) {
    return false;
  }
  while ((OMCU_I2C0->status & OMCU_I2C_STATUS_BUSY) != 0u) {
  }
  OMCU_I2C0->status = OMCU_I2C_STATUS_DONE |
                       OMCU_I2C_STATUS_ACK_ERROR |
                       OMCU_I2C_STATUS_COMMAND_ERROR;
  OMCU_I2C0->cmd = command;
  do {
    status = OMCU_I2C0->status;
  } while ((status & OMCU_I2C_STATUS_BUSY) != 0u);
  return (status & (OMCU_I2C_STATUS_DONE |
                    OMCU_I2C_STATUS_ACK_ERROR |
                    OMCU_I2C_STATUS_COMMAND_ERROR)) == OMCU_I2C_STATUS_DONE;
}

static inline bool omcu_i2c0_start(void) {
  return omcu_i2c0_command(OMCU_I2C_CMD_START);
}

static inline bool omcu_i2c0_stop(void) {
  return omcu_i2c0_command(OMCU_I2C_CMD_STOP);
}

static inline bool omcu_i2c0_write_byte(uint8_t byte) {
  OMCU_I2C0->data = byte;
  return omcu_i2c0_command(OMCU_I2C_CMD_WRITE);
}

// Set acknowledge=false for the final byte in a target-to-controller read.
static inline bool omcu_i2c0_read_byte(uint8_t *byte, bool acknowledge) {
  if (!omcu_i2c0_command(
        acknowledge ? OMCU_I2C_CMD_READ_ACK : OMCU_I2C_CMD_READ_NACK)) {
    return false;
  }
  if (byte != 0) {
    *byte = (uint8_t)OMCU_I2C0->data;
  }
  return true;
}

static inline void omcu_wdt0_start(
  uint32_t timeout,
  bool request_reset,
  bool enable_expiry_irq
) {
  OMCU_WDT0->ctrl = 0u;
  OMCU_WDT0->timeout = timeout;
  OMCU_WDT0->status = OMCU_WDT_STATUS_EXPIRED;
  OMCU_WDT0->feed = OMCU_WDT_FEED_MAGIC;
  OMCU_WDT0->ctrl = OMCU_WDT_CTRL_ENABLE |
                    (request_reset ? OMCU_WDT_CTRL_RESET_ENABLE : 0u) |
                    (enable_expiry_irq ? OMCU_WDT_CTRL_IRQ_ENABLE : 0u);
}

static inline void omcu_wdt0_feed(void) {
  OMCU_WDT0->feed = OMCU_WDT_FEED_MAGIC;
}

static inline void omcu_wdt0_stop(void) {
  OMCU_WDT0->ctrl = 0u;
}

static inline void omcu_pwm0_configure(
  uint16_t prescale,
  uint32_t period,
  uint32_t duty,
  bool invert
) {
  OMCU_PWM0->ctrl = 0u;
  OMCU_PWM0->prescale = prescale;
  OMCU_PWM0->period = period;
  OMCU_PWM0->duty = duty;
  OMCU_PWM0->ctrl = OMCU_PWM_CTRL_ENABLE |
                    (invert ? OMCU_PWM_CTRL_INVERT : 0u);
}

#endif  /* OMCU_H_ */
