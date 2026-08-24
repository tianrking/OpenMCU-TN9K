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
  const uint32_t required = OMCU_FEATURE_GPIO0 | OMCU_FEATURE_I2C0;

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    fail();
  }

  // The simulation fixture acknowledges 7-bit address 0x50, accepts one
  // payload byte, then returns 0x3C after a repeated START read address.
  omcu_i2c0_init(1u, false);
  if (!omcu_i2c0_start() ||
      !omcu_i2c0_write_byte(0xa0u) ||
      !omcu_i2c0_write_byte(0x5au) ||
      !omcu_i2c0_stop() ||
      !omcu_i2c0_start() ||
      !omcu_i2c0_write_byte(0xa1u) ||
      !omcu_i2c0_read_byte(&received, false) ||
      !omcu_i2c0_stop() ||
      received != 0x3cu) {
    fail();
  }

  omcu_gpio_enable_output(OMCU_SMOKE_PASS | OMCU_SMOKE_FAIL);
  omcu_gpio_set(OMCU_SMOKE_PASS);
  for (;;) {
  }
}
