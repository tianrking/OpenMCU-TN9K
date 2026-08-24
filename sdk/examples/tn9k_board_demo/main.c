#include "omcu_tn9k.h"

static void delay_cycles(volatile uint32_t cycles) {
  while (cycles-- != 0u) {
    __asm__ volatile ("nop");
  }
}

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

int main(void) {
  const uint32_t required = OMCU_FEATURE_GPIO0 |
                            OMCU_FEATURE_UART0 |
                            OMCU_FEATURE_SPI0 |
                            OMCU_FEATURE_I2C0 |
                            OMCU_FEATURE_PWM0 |
                            OMCU_FEATURE_WDT0;
  const uint32_t outputs = OMCU_TN9K_LED0 |
                           OMCU_TN9K_GPIO0 |
                           OMCU_TN9K_GPIO1 |
                           OMCU_TN9K_GPIO2;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    for (;;) {
    }
  }

  omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);
  uart_write_string("OpenMCU Tang Nano 9K board demo online\r\n");
  omcu_i2c0_init(134u, false);  /* approximately 100 kHz at 27 MHz */
  omcu_spi0_init(13u, false);   /* approximately 1 MHz mode-0 SCK */
  omcu_pwm0_configure(26u, 999u, 500u, false); /* approximately 1 kHz, 50% */
  omcu_wdt0_start(UINT32_C(27000000), true, false);
  omcu_gpio_enable_output(outputs);

  for (;;) {
    /* GPIO[6:8] are the three documented Tang expansion signals. */
    omcu_gpio_toggle(OMCU_TN9K_LED0 | OMCU_TN9K_GPIO0 | OMCU_TN9K_GPIO1 |
                     OMCU_TN9K_GPIO2);
    omcu_wdt0_feed();
    delay_cycles(6750000u);
  }
}
