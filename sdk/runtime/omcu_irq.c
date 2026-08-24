#include "omcu.h"

// Applications provide a strong definition to override this weak default.
// The weak default is deliberately fail-safe: it disables and acknowledges the
// reported OpenMCU external sources so an accidental unhandled level cannot
// create an interrupt-return storm.
void __attribute__((weak)) omcu_irq_dispatch(uint32_t pending) {
  uint32_t active = pending & OMCU_IRQ_EXTERNAL_MASK;

  OMCU_IRQCTRL->enable &= ~active;
  OMCU_IRQCTRL->clear = active;
}
