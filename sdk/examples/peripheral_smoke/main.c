#include "omcu.h"

enum {
  OMCU_SMOKE_PASS = 1u << 0,
  OMCU_SMOKE_FAIL = 1u << 1,
};

static void fail(void) {
  omcu_gpio_enable_output(OMCU_SMOKE_PASS | OMCU_SMOKE_FAIL);
  omcu_gpio_set(OMCU_SMOKE_FAIL);
  for (;;) {
  }
}

int main(void) {
  uint8_t received = 0u;
  const uint32_t required = OMCU_FEATURE_GPIO0 |
                            OMCU_FEATURE_SPI0 |
                            OMCU_FEATURE_WDT0 |
                            OMCU_FEATURE_PWM0;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    fail();
  }

  omcu_pwm0_configure(0u, 3u, 2u, false);
  omcu_wdt0_start(UINT32_C(0x0000ffff), false, false);
  omcu_spi0_init(1u, false);

  // The simulator ties MISO high, so a completed byte transfer must read FF.
  if (!omcu_spi0_transfer(0xa5u, &received) || received != 0xffu) {
    fail();
  }
  omcu_wdt0_feed();

  omcu_gpio_enable_output(OMCU_SMOKE_PASS | OMCU_SMOKE_FAIL);
  omcu_gpio_set(OMCU_SMOKE_PASS);
  for (;;) {
  }
}
