#include "omcu.h"

int main(void) {
  /* The Tang platform reset wrapper must restart the whole MCU after expiry. */
  omcu_wdt0_start(20u, true, false);
  for (;;) {
  }
}
