#include "omcu_tn9k.h"

enum {
  SELFTEST_GPIO_MASK = 0x00000fffu,
  SELFTEST_REQUIRED_FEATURES = 0x000fffffu,
  SELFTEST_SRAM_WORDS = 4096u,
  SELFTEST_TIMEOUT_TICKS = 2000000u,
};

#define SELFTEST_RESET_MAGIC UINT32_C(0x53465431)

typedef struct {
  uint32_t magic;
  uint32_t magic_inverse;
  uint32_t expected_reset_count;
  uint32_t count_inverse;
} selftest_reset_probe_t;

static volatile selftest_reset_probe_t reset_probe
  __attribute__((section(".noinit.omcu_selftest")));
static volatile uint32_t sram_probe[SELFTEST_SRAM_WORDS];
static volatile uint32_t isa_left = 37u;
static volatile uint32_t isa_right = 101u;
static volatile int32_t isa_signed_left = -301;
static volatile int32_t isa_signed_right = 7;
static uint32_t pass_count;
static uint32_t fail_count;

static void uart_write_string(const char *text) {
  while (*text != '\0') {
    omcu_uart0_write_byte((uint8_t)*text);
    ++text;
  }
}

static void uart_write_hex32(uint32_t value) {
  static const char digits[] = "0123456789abcdef";
  int shift;

  uart_write_string("0x");
  for (shift = 28; shift >= 0; shift -= 4) {
    omcu_uart0_write_byte((uint8_t)digits[(value >> (uint32_t)shift) & 0x0fu]);
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

static void delay_ticks(uint32_t ticks) {
  const uint64_t start = omcu_sysctrl_run_ticks();
  while ((omcu_sysctrl_run_ticks() - start) < ticks) {
  }
}

static bool reset_probe_is_valid(void) {
  return reset_probe.magic == SELFTEST_RESET_MAGIC &&
         reset_probe.magic_inverse == ~SELFTEST_RESET_MAGIC &&
         reset_probe.count_inverse == ~reset_probe.expected_reset_count;
}

static void arm_watchdog_reset_test(void) {
  const uint32_t expected = omcu_sysctrl_reset_count() + 1u;

  uart_write_string("OMCU_SELFTEST V1 PHASE WDT_RESET_ARM\r\n");
  uart_write_string("INFO RESET_COUNT ");
  uart_write_hex32(omcu_sysctrl_reset_count());
  uart_write_string("\r\n");

  reset_probe.expected_reset_count = expected;
  reset_probe.count_inverse = ~expected;
  reset_probe.magic_inverse = ~SELFTEST_RESET_MAGIC;
  reset_probe.magic = SELFTEST_RESET_MAGIC;

  /* Let the final UART byte leave the wire before the whole SoC is reset. */
  delay_ticks(OMCU_TN9K_SYSCLK_HZ / 100u);
  omcu_wdt0_start(OMCU_TN9K_SYSCLK_HZ / 100u, true, false);
  for (;;) {
  }
}

static bool test_sram(void) {
  uint32_t index;

  for (index = 0u; index < SELFTEST_SRAM_WORDS; ++index) {
    sram_probe[index] = UINT32_C(0xa5a50000) ^
                        (index * UINT32_C(0x9e3779b9));
  }
  for (index = 0u; index < SELFTEST_SRAM_WORDS; ++index) {
    const uint32_t expected = UINT32_C(0xa5a50000) ^
                              (index * UINT32_C(0x9e3779b9));
    if (sram_probe[index] != expected) {
      return false;
    }
  }
  for (index = 0u; index < SELFTEST_SRAM_WORDS; ++index) {
    sram_probe[index] = ~index;
  }
  for (index = 0u; index < SELFTEST_SRAM_WORDS; ++index) {
    if (sram_probe[index] != ~index) {
      return false;
    }
  }
  return true;
}

static bool test_rv32im(void) {
  const uint32_t product = isa_left * isa_right;
  const uint32_t quotient = product / isa_left;
  const uint32_t remainder = product % isa_left;
  const int32_t signed_quotient = isa_signed_left / isa_signed_right;
  const int32_t signed_remainder = isa_signed_left % isa_signed_right;

  return product == 3737u && quotient == 101u && remainder == 0u &&
         signed_quotient == -43 && signed_remainder == 0;
}

static bool test_sysctrl_ticks(void) {
  const uint64_t before = omcu_sysctrl_run_ticks();
  uint64_t after;

  delay_ticks(1024u);
  after = omcu_sysctrl_run_ticks();
  return after > before && (after - before) >= 1024u;
}

static bool test_gpio_pad_readback(void) {
  const uint32_t pattern_a = 0x00000a55u;
  const uint32_t pattern_b = 0x000005aau;
  bool passed;

  OMCU_PINMUX->ctrl = 0u;
  OMCU_GPIO0->filter_ctrl = 0u;
  OMCU_GPIO0->filter_cycles = 0u;
  omcu_gpio_clear(SELFTEST_GPIO_MASK);
  omcu_gpio_enable_output(SELFTEST_GPIO_MASK);
  omcu_gpio_set(pattern_a);
  delay_ticks(128u);
  passed = (OMCU_GPIO0->oe & SELFTEST_GPIO_MASK) == SELFTEST_GPIO_MASK &&
           (OMCU_GPIO0->out & SELFTEST_GPIO_MASK) == pattern_a &&
           (OMCU_GPIO0->in & SELFTEST_GPIO_MASK) == pattern_a;

  omcu_gpio_clear(SELFTEST_GPIO_MASK);
  omcu_gpio_set(pattern_b);
  delay_ticks(128u);
  passed = passed &&
           (OMCU_GPIO0->out & SELFTEST_GPIO_MASK) == pattern_b &&
           (OMCU_GPIO0->in & SELFTEST_GPIO_MASK) == pattern_b;

  omcu_gpio_clear(SELFTEST_GPIO_MASK);
  omcu_gpio_disable_output(SELFTEST_GPIO_MASK);
  return passed;
}

static bool test_gpio_reliability_mmio(void) {
  const uint32_t mask = OMCU_TN9K_GPIO0 | OMCU_TN9K_GPIO2 |
                        OMCU_TN9K_GPIO11;
  bool passed = omcu_gpio_configure_independent_filter(
    mask, OMCU_GPIO_FILTER_CTRL_DEPTH_4
  );

  passed = passed && omcu_gpio_filter_mask() == mask &&
           omcu_gpio_filter_ctrl() ==
             (OMCU_GPIO_FILTER_CTRL_INDEPENDENT_ENABLE |
              OMCU_GPIO_FILTER_CTRL_DEPTH_4);
  (void)omcu_gpio_configure_filter(0u);
  return passed;
}

static bool test_irqctrl_force(void) {
  const uint32_t sources = OMCU_IRQ_GPIO0 | OMCU_IRQ_TIMER0;
  const uint32_t previous_mask = omcu_irq_global_disable();
  bool passed;

  omcu_irqctrl_set_enable(0u);
  omcu_irqctrl_ack(OMCU_IRQ_EXTERNAL_MASK);
  omcu_irqctrl_set_enable(sources);
  omcu_irqctrl_force(sources);
  delay_ticks(16u);
  passed = (omcu_irqctrl_pending() & sources) == sources &&
           omcu_irqctrl_active() == sources &&
           omcu_irqctrl_highest() == 8u;
  omcu_irqctrl_ack(OMCU_IRQ_GPIO0);
  delay_ticks(8u);
  passed = passed && omcu_irqctrl_active() == OMCU_IRQ_TIMER0 &&
           omcu_irqctrl_highest() == 10u;
  omcu_irqctrl_ack(OMCU_IRQ_TIMER0);
  omcu_irqctrl_set_enable(0u);
  omcu_irq_restore(previous_mask);
  return passed && omcu_irqctrl_active() == 0u;
}

static bool test_timer0_compare(void) {
  bool completed;
  bool passed;

  OMCU_TIMER0->ctrl = 0u;
  OMCU_TIMER0->prescale = 0u;
  OMCU_TIMER0->count = 0u;
  OMCU_TIMER0->compare = 1000u;
  OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
  OMCU_TIMER0->ctrl = OMCU_TIMER_CTRL_ENABLE;
  completed = wait_mask(&OMCU_TIMER0->status, OMCU_TIMER_STATUS_PENDING,
                        true, SELFTEST_TIMEOUT_TICKS);
  passed = completed && (OMCU_TIMER0->ctrl & OMCU_TIMER_CTRL_ENABLE) == 0u &&
           OMCU_TIMER0->count == 1000u;
  OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
  OMCU_TIMER0->ctrl = 0u;
  return passed;
}

static bool test_alarm0_compare(void) {
  bool passed = omcu_alarm0_start(0u) &&
                omcu_alarm0_schedule_after(0u, 1000u, 0u, false, false);

  passed = passed && wait_mask(&OMCU_ALARM0->pending, 1u, true,
                               SELFTEST_TIMEOUT_TICKS);
  omcu_alarm0_clear_pending(OMCU_ALARM_CHANNEL_MASK);
  OMCU_ALARM0->channel_enable = 0u;
  OMCU_ALARM0->ctrl = 0u;
  OMCU_TIMER0->ctrl = 0u;
  return passed;
}

static bool test_pwm0_timebase(void) {
  uint32_t first;
  uint32_t current;
  uint32_t attempts;
  bool moved = false;

  omcu_pwm0_configure(0u, 31u, 13u, false);
  first = OMCU_PWM0->count;
  for (attempts = 0u; attempts < 256u; ++attempts) {
    current = OMCU_PWM0->count;
    if (current != first) {
      moved = true;
    }
    if (current > 31u) {
      OMCU_PWM0->ctrl = 0u;
      return false;
    }
  }
  OMCU_PWM0->ctrl = 0u;
  return moved && OMCU_PWM0->prescale == 0u &&
         OMCU_PWM0->period == 31u && OMCU_PWM0->duty == 13u;
}

static bool test_pwm1_pad_readback(void) {
  uint32_t seen_high = 0u;
  uint32_t seen_low = 0u;
  uint32_t attempts;
  const uint32_t pins = OMCU_TN9K_GPIO4 | OMCU_TN9K_GPIO5 |
                        OMCU_TN9K_GPIO6 | OMCU_TN9K_GPIO7;

  omcu_gpio_disable_output(pins);
  omcu_pwm1_configure(0u, 31u, 4u, 8u, 16u, 28u, 0u);
  if (!omcu_pinmux_pwm1_enable(true)) {
    OMCU_PWM1->ctrl = 0u;
    return false;
  }
  for (attempts = 0u; attempts < 4096u; ++attempts) {
    const uint32_t sample = OMCU_GPIO0->in & pins;
    seen_high |= sample;
    seen_low |= (~sample) & pins;
  }
  OMCU_PWM1->ctrl = 0u;
  (void)omcu_pinmux_pwm1_enable(false);
  return (seen_high & pins) == pins && (seen_low & pins) == pins;
}

static bool test_timer1_compare(void) {
  bool passed;

  omcu_timer1_configure(0u, 1000u, 0u, OMCU_TIMER1_CTRL_ENABLE);
  passed = wait_mask(&OMCU_TIMER1->status, OMCU_TIMER1_STATUS_COMPARE,
                     true, SELFTEST_TIMEOUT_TICKS) &&
           (OMCU_TIMER1->ctrl & OMCU_TIMER1_CTRL_ENABLE) == 0u &&
           OMCU_TIMER1->count == 1000u;
  OMCU_TIMER1->ctrl = 0u;
  omcu_timer1_clear_status(OMCU_TIMER1_STATUS_COMPARE);
  return passed;
}

static bool test_uart1_tx_pad(void) {
  bool saw_idle_high;
  bool saw_start_low = false;
  bool returned_high;
  uint32_t attempts;

  omcu_gpio_disable_output(OMCU_TN9K_GPIO10 | OMCU_TN9K_GPIO11);
  if (!omcu_tn9k_uart1_init(omcu_tn9k_uart_bauddiv(9600u), false)) {
    return false;
  }
  delay_ticks(128u);
  saw_idle_high = (OMCU_GPIO0->in & OMCU_TN9K_GPIO10) != 0u;
  omcu_uart1_write_byte(0x00u);
  for (attempts = 0u; attempts < 200000u; ++attempts) {
    if ((OMCU_GPIO0->in & OMCU_TN9K_GPIO10) == 0u) {
      saw_start_low = true;
      break;
    }
  }
  if (!wait_mask(&OMCU_UART1->status, OMCU_UART_STATUS_TX_READY,
                 true, SELFTEST_TIMEOUT_TICKS)) {
    (void)omcu_tn9k_uart1_release_pins();
    return false;
  }
  delay_ticks(128u);
  returned_high = (OMCU_GPIO0->in & OMCU_TN9K_GPIO10) != 0u;
  (void)omcu_tn9k_uart1_release_pins();
  OMCU_UART1->ctrl = 0u;
  return saw_idle_high && saw_start_low && returned_high;
}

static bool test_spi0_engine(void) {
  uint8_t received = 0u;
  bool passed;

  omcu_spi0_init(4u, false);
  passed = omcu_spi0_transfer(0xa5u, &received) && received == 0xffu &&
           !omcu_spi0_cs_active();
  OMCU_SPI0->ctrl = 0u;
  return passed;
}

static bool test_i2c0_idle_start_stop(void) {
  bool start_complete;
  bool stop_complete;
  uint32_t status;

  omcu_i2c0_init(20u, false);
  OMCU_I2C0->cmd = OMCU_I2C_CMD_START;
  start_complete = wait_mask(&OMCU_I2C0->status, OMCU_I2C_STATUS_BUSY,
                             false, SELFTEST_TIMEOUT_TICKS);
  status = OMCU_I2C0->status;
  start_complete = start_complete &&
                   (status & (OMCU_I2C_STATUS_DONE |
                              OMCU_I2C_STATUS_BUS_ACTIVE)) ==
                     (OMCU_I2C_STATUS_DONE | OMCU_I2C_STATUS_BUS_ACTIVE) &&
                   (status & (OMCU_I2C_STATUS_ACK_ERROR |
                              OMCU_I2C_STATUS_COMMAND_ERROR)) == 0u;
  if (!start_complete) {
    OMCU_I2C0->ctrl = 0u;
    return false;
  }

  OMCU_I2C0->status = OMCU_I2C_STATUS_DONE;
  OMCU_I2C0->cmd = OMCU_I2C_CMD_STOP;
  stop_complete = wait_mask(&OMCU_I2C0->status, OMCU_I2C_STATUS_BUSY,
                            false, SELFTEST_TIMEOUT_TICKS);
  status = OMCU_I2C0->status;
  stop_complete = stop_complete &&
                  (status & OMCU_I2C_STATUS_DONE) != 0u &&
                  (status & (OMCU_I2C_STATUS_BUS_ACTIVE |
                             OMCU_I2C_STATUS_COMMAND_ERROR)) == 0u;
  OMCU_I2C0->ctrl = 0u;
  return stop_complete;
}

static bool test_pinmux_mmio(void) {
  const uint32_t mask = OMCU_PINMUX_CTRL_UART1_ENABLE |
                        OMCU_PINMUX_CTRL_PWM1_ENABLE |
                        OMCU_PINMUX_CTRL_TIMER1_ENABLE |
                        OMCU_PINMUX_CTRL_PULSE0_ENABLE |
                        OMCU_PINMUX_CTRL_FAULT0_ENABLE;

  OMCU_PINMUX->ctrl = mask;
  if (OMCU_PINMUX->ctrl != mask) {
    OMCU_PINMUX->ctrl = 0u;
    return false;
  }
  OMCU_PINMUX->ctrl = 0u;
  return OMCU_PINMUX->ctrl == 0u;
}

static bool test_pulse0_mmio(void) {
  bool passed = omcu_pulse0_configure(2u, true, 7u, false);

  passed = passed && OMCU_PULSE0->ctrl == OMCU_PULSE_CTRL_ENABLE &&
           OMCU_PULSE0->input_select == 2u &&
           OMCU_PULSE0->edge == OMCU_PULSE_EDGE_FALLING &&
           OMCU_PULSE0->filter == 7u;
  OMCU_PULSE0->ctrl = 0u;
  omcu_pulse0_clear();
  return passed;
}

static bool test_fault0_mmio(void) {
  OMCU_FAULT0->ctrl = 0u;
  OMCU_FAULT0->filter = 7u;
  return OMCU_FAULT0->ctrl == 0u && OMCU_FAULT0->filter == 7u &&
         (OMCU_FAULT0->gpio_hiz_mask & SELFTEST_GPIO_MASK) ==
           SELFTEST_GPIO_MASK;
}

static bool test_wdt_supervisor(void) {
  bool passed = omcu_wdt0_start_supervisor(
    OMCU_TN9K_SYSCLK_HZ,
    0u,
    0u,
    0x03u,
    false,
    false,
    false
  );

  passed = passed &&
           (OMCU_WDT0->ctrl & (OMCU_WDT_CTRL_ENABLE |
                               OMCU_WDT_CTRL_HEARTBEAT_ENABLE)) ==
             (OMCU_WDT_CTRL_ENABLE | OMCU_WDT_CTRL_HEARTBEAT_ENABLE) &&
           OMCU_WDT0->heartbeat_required == 0x03u &&
           omcu_wdt0_heartbeat_kick(0x01u) &&
           omcu_wdt0_heartbeat_kick(0x02u);
  delay_ticks(16u);
  passed = passed && (OMCU_WDT0->heartbeat_seen & 0x03u) == 0x03u;
  omcu_wdt0_feed();
  delay_ticks(16u);
  passed = passed && OMCU_WDT0->heartbeat_seen == 0u &&
           (OMCU_WDT0->status & OMCU_WDT_STATUS_FEED_REJECTED) == 0u;
  omcu_wdt0_stop();
  return passed;
}

static bool test_uart0_rx(void) {
  static const char expected[] = "PING";
  uint32_t index = 0u;
  const uint64_t start = omcu_sysctrl_run_ticks();

  while (omcu_uart0_rx_ready()) {
    (void)omcu_uart0_read_byte();
  }
  uart_write_string("READY UART0_RX\r\n");
  while ((omcu_sysctrl_run_ticks() - start) <
         (uint64_t)OMCU_TN9K_SYSCLK_HZ * 10u) {
    if (omcu_uart0_rx_ready()) {
      const uint8_t byte = omcu_uart0_read_byte();
      if (byte == '\r' || byte == '\n') {
        if (index == 4u) {
          uart_write_string("PONG\r\n");
          return true;
        }
        index = 0u;
      } else if (byte == (uint8_t)expected[index]) {
        ++index;
      } else {
        index = (byte == (uint8_t)expected[0]) ? 1u : 0u;
      }
    }
  }
  return false;
}

int main(void) {
  const uint32_t abi = OMCU_SYSCTRL->abi;
  const uint32_t features = OMCU_SYSCTRL->features;
  const uint32_t reset_cause = omcu_sysctrl_reset_cause();
  const uint32_t reset_count = omcu_sysctrl_reset_count();
  bool watchdog_reset_passed;

  omcu_uart0_init(omcu_tn9k_uart_bauddiv(115200u), false);

  if (!reset_probe_is_valid()) {
    arm_watchdog_reset_test();
  }

  watchdog_reset_passed = reset_cause == OMCU_RESET_CAUSE_WATCHDOG &&
                          reset_count == reset_probe.expected_reset_count;
  reset_probe.magic = 0u;
  reset_probe.magic_inverse = 0u;
  reset_probe.expected_reset_count = 0u;
  reset_probe.count_inverse = 0u;

  uart_write_string("OMCU_SELFTEST V1 BEGIN\r\n");
  uart_write_string("INFO CHIP_ID ");
  uart_write_hex32(OMCU_SYSCTRL->chip_id);
  uart_write_string("\r\nINFO ABI ");
  uart_write_hex32(abi);
  uart_write_string("\r\nINFO FEATURES ");
  uart_write_hex32(features);
  uart_write_string("\r\nINFO BUILD_ID ");
  uart_write_hex32(OMCU_SYSCTRL->build_id);
  uart_write_string("\r\nINFO MEMORY_KIB ");
  uart_write_hex32(OMCU_SYSCTRL->memory_kib);
  uart_write_string("\r\nINFO RESET_CAUSE ");
  uart_write_hex32(reset_cause);
  uart_write_string("\r\nINFO RESET_COUNT ");
  uart_write_hex32(reset_count);
  uart_write_string("\r\n");

  record_result("HW_IDENTITY",
                OMCU_SYSCTRL->chip_id == OMCU_CHIP_ID &&
                abi == ((OMCU_HW_ABI_MAJOR << 16u) | OMCU_HW_ABI_MINOR) &&
                OMCU_SYSCTRL->build_id == 1u);
  record_result("FEATURES",
                (features & SELFTEST_REQUIRED_FEATURES) ==
                  SELFTEST_REQUIRED_FEATURES);
  record_result("MEMORY_GEOMETRY", OMCU_SYSCTRL->memory_kib == 0x002c0004u);
  record_result("BOOTLOADER_REQUEST_CAPABILITY",
                omcu_bootloader_request_supported());
  record_result("WDT_RESET", watchdog_reset_passed);
  record_result("SRAM_16K", test_sram());
  record_result("RV32IM", test_rv32im());
  record_result("SYSCTRL_TICKS", test_sysctrl_ticks());
  record_result("GPIO_PAD_READBACK", test_gpio_pad_readback());
  record_result("GPIO_RELIABILITY_MMIO", test_gpio_reliability_mmio());
  record_result("IRQCTRL_FORCE", test_irqctrl_force());
  record_result("TIMER0_COMPARE", test_timer0_compare());
  record_result("ALARM0_COMPARE", test_alarm0_compare());
  record_result("PWM0_TIMEBASE", test_pwm0_timebase());
  record_result("PWM1_PAD_READBACK", test_pwm1_pad_readback());
  record_result("TIMER1_COMPARE", test_timer1_compare());
  record_result("UART1_TX_PAD", test_uart1_tx_pad());
  record_result("SPI0_ENGINE_IDLE_MISO", test_spi0_engine());
  record_result("I2C0_IDLE_START_STOP", test_i2c0_idle_start_stop());
  record_result("PINMUX_MMIO", test_pinmux_mmio());
  record_result("PULSE0_MMIO", test_pulse0_mmio());
  record_result("FAULT0_MMIO", test_fault0_mmio());
  record_result("WDT_SUPERVISOR", test_wdt_supervisor());
  record_result("UART0_RX", test_uart0_rx());

  uart_write_string(fail_count == 0u ? "RESULT PASS pass=" :
                                          "RESULT FAIL pass=");
  uart_write_u32(pass_count);
  uart_write_string(" fail=");
  uart_write_u32(fail_count);
  uart_write_string("\r\n");

  omcu_gpio_enable_output(OMCU_TN9K_LED0 | OMCU_TN9K_LED5);
  if (fail_count == 0u) {
    omcu_gpio_set(OMCU_TN9K_LED0);
    omcu_gpio_clear(OMCU_TN9K_LED5);
  } else {
    omcu_gpio_clear(OMCU_TN9K_LED0);
    omcu_gpio_set(OMCU_TN9K_LED5);
  }
  for (;;) {
  }
}
