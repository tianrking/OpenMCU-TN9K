#include "omcu.h"

/*
 * These non-constant objects deliberately live in .data.  The test therefore
 * verifies startup data relocation as well as actual M-extension instructions;
 * a compiler cannot fold the operations into constants.
 */
static volatile uint32_t multiply_left = 37u;
static volatile uint32_t multiply_right = 101u;
static volatile int32_t signed_left = -301;
static volatile int32_t signed_right = 7;

enum {
  OMCU_ISA_PASS = 1u << 0,
  OMCU_ISA_FAIL = 1u << 1,
};

int main(void) {
  const uint32_t product = multiply_left * multiply_right;
  const uint32_t quotient = product / multiply_left;
  const uint32_t remainder = product % multiply_left;
  const int32_t signed_quotient = signed_left / signed_right;
  const int32_t signed_remainder = signed_left % signed_right;

  omcu_gpio_enable_output(OMCU_ISA_PASS | OMCU_ISA_FAIL);

  if (product == 3737u && quotient == 101u && remainder == 0u &&
      signed_quotient == -43 && signed_remainder == 0) {
    omcu_gpio_set(OMCU_ISA_PASS);
  } else {
    omcu_gpio_set(OMCU_ISA_FAIL);
  }

  for (;;) {
  }
}
