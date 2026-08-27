#include "omcu_tn9k.h"

enum {
  LOOPBACK_TIMEOUT_TICKS = 3000000u,
};

static uint32_t pass_count;
static uint32_t fail_count;

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

static void uart_write_u32(uint32_t value) {
  char digits[10];
  uint32_t count = 0u;

  do {
    digits[count] = (char)('0' + (value % 10u));
    value /= 10u;
    ++count;
  } while (value != 0u);
  while (count != 0u) {
    --count;
    omcu_uart0_write_byte((uint8_t)digits[count]);
  }
}

static void record_result(const char *name, bool passed) {
  uart_write_string(passed ? "PASS " : "FAIL ");
  uart_write_string(name);
  uart_write_string("\r\n");
  if (passed) {
    ++pass_count;
  } else {
    ++fail_count;
  }
}

static void delay_ticks(uint32_t ticks) {
  const uint64_t start = omcu_sysctrl_run_ticks();
  while ((omcu_sysctrl_run_ticks() - start) < ticks) {
  }
}

static bool wait_mask(
  volatile const uint32_t *reg,
  uint32_t mask,
  bool set,
  uint32_t timeout_ticks
) {
  const uint64_t start = omcu_sysctrl_run_ticks();

  for (;;) {
    const bool is_set = (*reg & mask) == mask;
    if (is_set == set) {
      return true;
    }
    if ((omcu_sysctrl_run_ticks() - start) > timeout_ticks) {
      return false;
    }
  }
}

static bool test_harness_gpio(void) {
  const uint32_t outputs = OMCU_TN9K_GPIO4 |
                           OMCU_TN9K_GPIO5 |
                           OMCU_TN9K_GPIO6;
  const uint32_t inputs = OMCU_TN9K_GPIO3 |
                          OMCU_TN9K_GPIO8 |
                          OMCU_TN9K_GPIO9;
  bool passed;

  OMCU_PINMUX->ctrl = 0u;
  OMCU_GPIO0->filter_ctrl = 0u;
  OMCU_GPIO0->filter_cycles = 0u;
  omcu_gpio_disable_output(inputs);
  omcu_gpio_clear(outputs);
  omcu_gpio_enable_output(outputs);

  omcu_gpio_set(OMCU_TN9K_GPIO4 | OMCU_TN9K_GPIO6);
  delay_ticks(128u);
  passed = (OMCU_GPIO0->in & inputs) ==
           (OMCU_TN9K_GPIO3 | OMCU_TN9K_GPIO8);

  omcu_gpio_clear(outputs);
  omcu_gpio_set(OMCU_TN9K_GPIO5);
  delay_ticks(128u);
  passed = passed &&
           (OMCU_GPIO0->in & inputs) == OMCU_TN9K_GPIO9;

  omcu_gpio_clear(outputs);
  omcu_gpio_disable_output(outputs);
  return passed;
}

static bool test_uart1_loopback(void) {
  static const uint8_t patterns[] = {
    0x00u, 0x55u, 0xaau, 0xffu, 0x4fu, 0x4du, 0x43u, 0x55u,
  };
  uint32_t index;

  omcu_gpio_disable_output(OMCU_TN9K_GPIO10 | OMCU_TN9K_GPIO11);
  if (!omcu_tn9k_uart1_init(omcu_tn9k_uart_bauddiv(115200u), false)) {
    return false;
  }
  while (omcu_uart1_rx_ready()) {
    (void)omcu_uart1_read_byte();
  }
  for (index = 0u; index < sizeof(patterns); ++index) {
    omcu_uart1_write_byte(patterns[index]);
    if (!wait_mask(&OMCU_UART1->status, OMCU_UART_STATUS_RX_VALID,
                   true, LOOPBACK_TIMEOUT_TICKS) ||
        omcu_uart1_read_byte() != patterns[index]) {
      (void)omcu_tn9k_uart1_release_pins();
      OMCU_UART1->ctrl = 0u;
      return false;
    }
  }
  index = OMCU_UART1->status & (OMCU_UART_STATUS_RX_OVERRUN |
                                OMCU_UART_STATUS_RX_FRAMING_ERROR);
  (void)omcu_tn9k_uart1_release_pins();
  OMCU_UART1->ctrl = 0u;
  return index == 0u;
}

static bool test_spi0_loopback(void) {
  static const uint8_t patterns[] = {
    0x00u, 0x01u, 0x55u, 0xaau, 0x80u, 0xfeu, 0xffu,
  };
  uint32_t index;

  omcu_spi0_init(13u, false);
  for (index = 0u; index < sizeof(patterns); ++index) {
    uint8_t received = 0u;
    if (!omcu_spi0_transfer(patterns[index], &received) ||
        received != patterns[index]) {
      OMCU_SPI0->ctrl = 0u;
      return false;
    }
  }
  OMCU_SPI0->ctrl = 0u;
  return true;
}

static void drive_encoder_state(uint32_t state) {
  const uint32_t outputs = OMCU_TN9K_GPIO4 | OMCU_TN9K_GPIO5;

  omcu_gpio_clear(outputs);
  if ((state & 2u) != 0u) {
    omcu_gpio_set(OMCU_TN9K_GPIO4);
  }
  if ((state & 1u) != 0u) {
    omcu_gpio_set(OMCU_TN9K_GPIO5);
  }
  delay_ticks(128u);
}

static bool test_timer1_encoder_loopback(void) {
  static const uint8_t forward[] = {1u, 3u, 2u, 0u};
  static const uint8_t reverse[] = {2u, 3u, 1u, 0u};
  const uint32_t outputs = OMCU_TN9K_GPIO4 | OMCU_TN9K_GPIO5;
  const uint32_t ctrl = OMCU_TIMER1_CTRL_ENABLE |
                        OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE |
                        OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE |
                        OMCU_TIMER1_CTRL_QUADRATURE_ENABLE;
  uint32_t cycle;
  uint32_t phase;
  bool passed;

  omcu_gpio_clear(outputs);
  omcu_gpio_enable_output(outputs);
  drive_encoder_state(0u);
  if (!omcu_tn9k_timer1_configure(0u, UINT16_MAX, 3u, ctrl)) {
    omcu_gpio_disable_output(outputs);
    return false;
  }
  delay_ticks(256u);
  omcu_timer1_set_encoder_position(0);
  omcu_timer1_clear_status(OMCU_TIMER1_STATUS_CAPTURE_A |
                           OMCU_TIMER1_STATUS_CAPTURE_B |
                           OMCU_TIMER1_STATUS_ENCODER_STEP |
                           OMCU_TIMER1_STATUS_ENCODER_ILLEGAL);

  for (cycle = 0u; cycle < 8u; ++cycle) {
    for (phase = 0u; phase < sizeof(forward); ++phase) {
      drive_encoder_state(forward[phase]);
    }
  }
  passed = omcu_timer1_encoder_position() == 32 &&
           (OMCU_TIMER1->status &
            (OMCU_TIMER1_STATUS_CAPTURE_A |
             OMCU_TIMER1_STATUS_CAPTURE_B |
             OMCU_TIMER1_STATUS_ENCODER_STEP)) ==
            (OMCU_TIMER1_STATUS_CAPTURE_A |
             OMCU_TIMER1_STATUS_CAPTURE_B |
             OMCU_TIMER1_STATUS_ENCODER_STEP) &&
           (OMCU_TIMER1->status & OMCU_TIMER1_STATUS_ENCODER_ILLEGAL) == 0u;

  for (cycle = 0u; cycle < 8u; ++cycle) {
    for (phase = 0u; phase < sizeof(reverse); ++phase) {
      drive_encoder_state(reverse[phase]);
    }
  }
  passed = passed && omcu_timer1_encoder_position() == 0 &&
           (OMCU_TIMER1->status & OMCU_TIMER1_STATUS_ENCODER_ILLEGAL) == 0u;

  OMCU_TIMER1->ctrl = 0u;
  (void)omcu_tn9k_timer1_release_pins();
  omcu_gpio_clear(outputs);
  omcu_gpio_disable_output(outputs);
  return passed;
}

static bool wait_timer1_captures(uint16_t *capture_a, uint16_t *capture_b) {
  const uint32_t captures = OMCU_TIMER1_STATUS_CAPTURE_A |
                            OMCU_TIMER1_STATUS_CAPTURE_B;

  if (!wait_mask(&OMCU_TIMER1->status, captures, true,
                 LOOPBACK_TIMEOUT_TICKS)) {
    return false;
  }
  *capture_a = (uint16_t)OMCU_TIMER1->capture_a;
  *capture_b = (uint16_t)OMCU_TIMER1->capture_b;
  omcu_timer1_clear_status(captures);
  return true;
}

static bool test_pwm1_timer1_loopback(void) {
  const uint32_t timer_ctrl = OMCU_TIMER1_CTRL_ENABLE |
                              OMCU_TIMER1_CTRL_CAPTURE_A_ENABLE |
                              OMCU_TIMER1_CTRL_CAPTURE_B_ENABLE;
  uint16_t capture_a_first = 0u;
  uint16_t capture_b_first = 0u;
  uint16_t capture_a_second = 0u;
  uint16_t capture_b_second = 0u;
  uint16_t delta_a;
  uint16_t delta_b;
  bool passed;

  omcu_gpio_disable_output(OMCU_TN9K_GPIO4 | OMCU_TN9K_GPIO5 |
                           OMCU_TN9K_GPIO8 | OMCU_TN9K_GPIO9);
  if (!omcu_tn9k_timer1_configure(0u, UINT16_MAX, 0u, timer_ctrl) ||
      !omcu_tn9k_pwm1_configure(0u, 1023u, 256u, 512u, 768u, 900u, 0u)) {
    return false;
  }
  delay_ticks(2048u);
  omcu_timer1_clear_status(OMCU_TIMER1_STATUS_CAPTURE_A |
                           OMCU_TIMER1_STATUS_CAPTURE_B);
  passed = wait_timer1_captures(&capture_a_first, &capture_b_first) &&
           wait_timer1_captures(&capture_a_second, &capture_b_second);
  delta_a = (uint16_t)(capture_a_second - capture_a_first);
  delta_b = (uint16_t)(capture_b_second - capture_b_first);
  passed = passed && delta_a >= 1000u && delta_a <= 1050u &&
           delta_b >= 1000u && delta_b <= 1050u;

  OMCU_PWM1->ctrl = 0u;
  OMCU_TIMER1->ctrl = 0u;
  (void)omcu_tn9k_pwm1_release_pins();
  (void)omcu_tn9k_timer1_release_pins();
  return passed;
}

static bool test_pwm0_pulse0_loopback(void) {
  const uint64_t start = omcu_sysctrl_run_ticks();
  uint16_t period;
  bool passed;

  omcu_gpio_disable_output(OMCU_TN9K_GPIO0 |
                           OMCU_TN9K_GPIO1 |
                           OMCU_TN9K_GPIO2);
  if (!omcu_tn9k_pulse0_configure(0u, false, 2u, false)) {
    return false;
  }
  omcu_pulse0_clear();
  omcu_pwm0_configure(0u, 2699u, 1350u, false);
  while (omcu_pulse0_count() < 5u &&
         (omcu_sysctrl_run_ticks() - start) < LOOPBACK_TIMEOUT_TICKS) {
  }
  period = omcu_pulse0_period_ticks();
  passed = omcu_pulse0_count() >= 5u && omcu_pulse0_period_valid() &&
           period >= 2670u && period <= 2730u;

  OMCU_PWM0->ctrl = 0u;
  OMCU_PULSE0->ctrl = 0u;
  (void)omcu_tn9k_pulse0_release_pins();
  return passed;
}

static bool test_fault0_gpio_gate_loopback(void) {
  const uint32_t source = OMCU_TN9K_GPIO6;
  omcu_fault0_snapshot_t snapshot;
  bool passed;

  omcu_gpio_set(source);
  omcu_gpio_enable_output(source);
  delay_ticks(256u);
  if (!omcu_tn9k_fault0_configure(
        3u, false, false, false, false, true)) {
    omcu_gpio_disable_output(source);
    return false;
  }
  delay_ticks(128u);
  omcu_gpio_clear(source);
  passed = wait_mask(&OMCU_FAULT0->status, OMCU_FAULT_STATUS_TRIPPED,
                     true, LOOPBACK_TIMEOUT_TICKS) &&
           (OMCU_FAULT0->status & OMCU_FAULT_STATUS_INPUT_CLAIMED) != 0u;

  /* The trip makes every GPIO pad high-Z. The source wire therefore returns
   * high through the reviewed pad pull-up, making an active-low fault safe. */
  passed = passed && wait_mask(&OMCU_FAULT0->status,
                               OMCU_FAULT_STATUS_ACTIVE,
                               false, LOOPBACK_TIMEOUT_TICKS);
  omcu_gpio_set(source);
  passed = passed && omcu_fault0_snapshot_read(&snapshot) &&
           snapshot.tick != 0u && omcu_fault0_try_clear() &&
           !omcu_fault0_is_tripped();
  passed = passed && omcu_tn9k_fault0_release_pin();
  omcu_gpio_clear(source);
  omcu_gpio_disable_output(source);
  return passed;
}

int main(void) {
  const uint32_t required = OMCU_FEATURE_GPIO0 |
                            OMCU_FEATURE_UART0 |
                            OMCU_FEATURE_UART1 |
                            OMCU_FEATURE_SPI0 |
                            OMCU_FEATURE_PWM0 |
                            OMCU_FEATURE_PWM1 |
                            OMCU_FEATURE_TIMER1 |
                            OMCU_FEATURE_PULSE0 |
                            OMCU_FEATURE_FAULT0 |
                            OMCU_FEATURE_PINMUX;

  omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);
  uart_write_string("OMCU_LOOPBACK_SELFTEST V1 BEGIN\r\n");
  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    record_result("HARDWARE_CAPABILITIES", false);
  } else {
    record_result("HARDWARE_CAPABILITIES", true);
    record_result("HARNESS_GPIO", test_harness_gpio());
    record_result("UART1_LOOPBACK", test_uart1_loopback());
    record_result("SPI0_LOOPBACK", test_spi0_loopback());
    record_result("TIMER1_ENCODER_LOOPBACK", test_timer1_encoder_loopback());
    record_result("PWM1_TIMER1_LOOPBACK", test_pwm1_timer1_loopback());
    record_result("PWM0_PULSE0_LOOPBACK", test_pwm0_pulse0_loopback());
    record_result("FAULT0_GPIO_GATE_LOOPBACK",
                  test_fault0_gpio_gate_loopback());
  }

  uart_write_string(fail_count == 0u ? "RESULT PASS pass=" :
                                          "RESULT FAIL pass=");
  uart_write_u32(pass_count);
  uart_write_string(" fail=");
  uart_write_u32(fail_count);
  uart_write_string("\r\n");

  for (;;) {
  }
}
