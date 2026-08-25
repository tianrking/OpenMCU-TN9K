#include "omcu_devices.h"
#include "omcu_tn9k.h"

/*
 * Compile-ready P0 wiring template.  It intentionally uses static network
 * settings and only reports discovery on an LED; a production application
 * supplies its own socket protocol, timeout policy and physical HIL record.
 */
static const omcu_w5500_netinfo_t network = {
  .gateway = { 192u, 168u, 1u, 1u },
  .subnet = { 255u, 255u, 255u, 0u },
  .mac = { 0x02u, 0x4fu, 0x4du, 0x43u, 0x55u, 0x06u },
  .ip = { 192u, 168u, 1u, 60u },
};

int main(void) {
  uint8_t w5500_version = 0u;
  int32_t temperature_milli_c = 0;
  bool rtc_present;
  bool tmp102_present;
  bool w5500_present;
  omcu_rtc_time_t rtc;

  omcu_gpio_enable_output(OMCU_TN9K_LED0 | OMCU_TN9K_LED1 |
                          OMCU_TN9K_LED2);
  omcu_i2c0_init(134u, false);  /* 100 kHz with required external pull-ups. */
  omcu_spi0_init(13u, false);   /* approximately 1 MHz for first bring-up. */

  rtc_present = omcu_ds3231_read_time(OMCU_DS3231_DEFAULT_ADDRESS, &rtc,
                                      OMCU_BUS_DEFAULT_SPIN_LIMIT);
  tmp102_present = omcu_tmp102_read_temperature_milli_c(
    OMCU_TMP102_DEFAULT_ADDRESS, &temperature_milli_c,
    OMCU_BUS_DEFAULT_SPIN_LIMIT
  );
  w5500_present = omcu_w5500_initialize(&network, &w5500_version,
                                         OMCU_BUS_DEFAULT_SPIN_LIMIT) &&
                  w5500_version == OMCU_W5500_VERSION;

  if (rtc_present) {
    omcu_gpio_set(OMCU_TN9K_LED0);
  }
  if (tmp102_present && temperature_milli_c > -55000) {
    omcu_gpio_set(OMCU_TN9K_LED1);
  }
  if (w5500_present) {
    omcu_gpio_set(OMCU_TN9K_LED2);
  }

  for (;;) {
    /* Add application protocol work here; no FPGA recompilation is required. */
  }
}
