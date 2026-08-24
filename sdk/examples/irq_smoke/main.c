#include "omcu.h"

enum {
  OMCU_IRQ_SMOKE_PASS = 1u << 0,
  OMCU_IRQ_SMOKE_HANDLER_RAN = 1u << 1,
  OMCU_IRQ_SMOKE_FAIL = 1u << 2,
};

static volatile uint32_t timer_irq_seen;

// Strong application handler replacing the SDK's fail-safe weak default.
void omcu_irq_dispatch(uint32_t pending) {
  const uint32_t external = pending & OMCU_IRQ_EXTERNAL_MASK;

  if ((external & OMCU_IRQ_TIMER0) != 0u) {
    // Quiesce the originating peripheral before clearing the controller's
    // sticky source. This ordering also works for level-style UART/SPI/I2C
    // sources whose own status bits must be acknowledged first.
    OMCU_TIMER0->ctrl = 0u;
    OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
    omcu_irqctrl_ack(OMCU_IRQ_TIMER0);
    timer_irq_seen = 1u;
    omcu_gpio_set(OMCU_IRQ_SMOKE_HANDLER_RAN);
  }

  if ((external & ~OMCU_IRQ_TIMER0) != 0u) {
    // A smoke image has no handler for the other sources. Disable them safely
    // instead of returning into an interrupt storm.
    omcu_irqctrl_set_enable(OMCU_IRQCTRL->enable & ~external);
    omcu_irqctrl_ack(external & ~OMCU_IRQ_TIMER0);
    omcu_gpio_set(OMCU_IRQ_SMOKE_FAIL);
  }
}

int main(void) {
  const uint32_t required = OMCU_FEATURE_GPIO0 |
                            OMCU_FEATURE_TIMER0 |
                            OMCU_FEATURE_IRQCTRL;

  omcu_gpio_enable_output(OMCU_IRQ_SMOKE_PASS |
                          OMCU_IRQ_SMOKE_HANDLER_RAN |
                          OMCU_IRQ_SMOKE_FAIL);

  if (!omcu_hw_abi_is_compatible(OMCU_HW_ABI_MAJOR) ||
      !omcu_hw_has_feature(required)) {
    omcu_gpio_set(OMCU_IRQ_SMOKE_FAIL);
    for (;;) {
    }
  }

  omcu_irqctrl_set_enable(0u);
  omcu_irqctrl_ack(OMCU_IRQ_EXTERNAL_MASK);
  omcu_timer_start_periodic(0u, 32u);
  omcu_irqctrl_set_enable(OMCU_IRQ_TIMER0);
  (void)omcu_irq_global_enable();

  while (timer_irq_seen == 0u) {
    __asm__ volatile ("nop");
  }

  omcu_gpio_set(OMCU_IRQ_SMOKE_PASS);
  for (;;) {
  }
}
