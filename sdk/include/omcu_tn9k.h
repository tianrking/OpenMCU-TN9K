#ifndef OMCU_TN9K_H_
#define OMCU_TN9K_H_

/*
 * Tang Nano 9K board support definitions for the public OpenMCU SDK.
 *
 * This header describes the fixed board wrapper in
 * rtl/platform/tangnano9k/omcu_tn9k_bringup_top.sv.  It contains logical MCU
 * GPIO numbers, never raw FPGA package pin numbers; physical pins belong to
 * the reviewed CST and the board documentation.
 */

#include "omcu.h"

#define OMCU_TN9K_SYSCLK_HZ       UINT32_C(27000000)
#define OMCU_TN9K_LED0            (UINT32_C(1) << 0)
#define OMCU_TN9K_LED1            (UINT32_C(1) << 1)
#define OMCU_TN9K_LED2            (UINT32_C(1) << 2)
#define OMCU_TN9K_LED3            (UINT32_C(1) << 3)
#define OMCU_TN9K_LED4            (UINT32_C(1) << 4)
#define OMCU_TN9K_LED5            (UINT32_C(1) << 5)
#define OMCU_TN9K_GPIO0           (UINT32_C(1) << 6)
#define OMCU_TN9K_GPIO1           (UINT32_C(1) << 7)
#define OMCU_TN9K_GPIO2           (UINT32_C(1) << 8)

/* Rounded divider for the UART0 convention: clocks-per-bit minus one. */
static inline uint16_t omcu_tn9k_uart_bauddiv(uint32_t baud) {
  uint32_t clocks_per_bit;

  if (baud == 0u) {
    return 0u;
  }
  clocks_per_bit = (OMCU_TN9K_SYSCLK_HZ + (baud / 2u)) / baud;
  return (uint16_t)((clocks_per_bit == 0u) ? 0u : clocks_per_bit - 1u);
}

#endif  /* OMCU_TN9K_H_ */
