#ifndef OMCU_REGS_H_
#define OMCU_REGS_H_

/*
 * Generated from spec/omcu-v0.json by scripts/generate-sdk.ps1.
 * Do not hand-edit this file; change the reviewed specification instead.
 */

#include <stdint.h>

#define OMCU_ROM_BASE            UINT32_C(0x00000000)
#define OMCU_SRAM_BASE           UINT32_C(0x10000000)
#define OMCU_QSPI_XIP_BASE       UINT32_C(0x20000000)
#define OMCU_GPIO0_BASE          UINT32_C(0x40000000)
#define OMCU_UART0_BASE          UINT32_C(0x40001000)
#define OMCU_TIMER0_BASE         UINT32_C(0x40002000)
#define OMCU_SPI0_BASE           UINT32_C(0x40003000)
#define OMCU_I2C0_BASE           UINT32_C(0x40004000)
#define OMCU_WDT0_BASE           UINT32_C(0x40005000)
#define OMCU_SYSCTRL_BASE        UINT32_C(0x4000F000)

#define OMCU_HW_ABI_MAJOR      0u
#define OMCU_HW_ABI_MINOR      1u

#define OMCU_CHIP_ID             UINT32_C(0x4F4D4355)
#define OMCU_SYSCTRL_ABI_MAJOR_SHIFT 16u
#define OMCU_SYSCTRL_ABI_MAJOR_MASK UINT32_C(0xFFFF0000)
#define OMCU_SYSCTRL_ABI_MINOR_MASK UINT32_C(0x0000FFFF)

typedef struct {
  volatile uint32_t out; /* +0x00: output latch */
  volatile uint32_t out_set; /* +0x04: write-one-to-set */
  volatile uint32_t out_clr; /* +0x08: write-one-to-clear */
  volatile uint32_t out_xor; /* +0x0c: write-one-to-toggle */
  volatile uint32_t oe; /* +0x10: output-enable latch */
  volatile uint32_t oe_set; /* +0x14: write-one-to-set */
  volatile uint32_t oe_clr; /* +0x18: write-one-to-clear */
  uint32_t _reserved_1c;
  volatile const uint32_t in; /* +0x20: sampled input */
  volatile uint32_t rise_en; /* +0x24: rising-edge interrupt enable */
  volatile uint32_t fall_en; /* +0x28: falling-edge interrupt enable */
  volatile uint32_t irq_status; /* +0x2c: write-one-to-clear */
} omcu_gpio_regs_t;

typedef struct {
  volatile uint32_t data; /* +0x00: TX write / RX read byte */
  volatile uint32_t status; /* +0x04: TX ready, RX valid and sticky errors */
  volatile uint32_t bauddiv; /* +0x08: system clocks per UART bit minus one */
  volatile uint32_t ctrl; /* +0x0c: TX enable, RX enable, RX IRQ enable */
} omcu_uart_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: EN, IRQ_EN, AUTO_RELOAD */
  volatile uint32_t prescale; /* +0x04: 16-bit divider minus one */
  volatile uint32_t count; /* +0x08: current counter */
  volatile uint32_t compare; /* +0x0c: compare value */
  volatile uint32_t status; /* +0x10: pending, write-one-to-clear */
} omcu_timer_regs_t;

typedef struct {
  volatile const uint32_t chip_id; /* +0x00: OpenMCU chip identifier */
  volatile const uint32_t abi; /* +0x04: major in bits 31:16, minor in bits 15:0 */
  volatile const uint32_t features; /* +0x08: implemented peripheral feature bits */
  volatile const uint32_t build_id; /* +0x0c: platform build identifier */
  volatile const uint32_t memory_kib; /* +0x10: SRAM KiB in bits 31:16, ROM KiB in bits 15:0 */
} omcu_sysctrl_regs_t;

#define OMCU_GPIO0               ((omcu_gpio_regs_t *)(uintptr_t)OMCU_GPIO0_BASE)
#define OMCU_UART0               ((omcu_uart_regs_t *)(uintptr_t)OMCU_UART0_BASE)
#define OMCU_TIMER0              ((omcu_timer_regs_t *)(uintptr_t)OMCU_TIMER0_BASE)
#define OMCU_SYSCTRL             ((omcu_sysctrl_regs_t *)(uintptr_t)OMCU_SYSCTRL_BASE)

enum {
  OMCU_FEATURE_GPIO0               = 1u << 0,
  OMCU_FEATURE_UART0               = 1u << 1,
  OMCU_FEATURE_TIMER0              = 1u << 2,
  OMCU_TIMER_CTRL_ENABLE           = 1u << 0,
  OMCU_TIMER_CTRL_IRQ_ENABLE       = 1u << 1,
  OMCU_TIMER_CTRL_AUTO_RELOAD      = 1u << 2,
  OMCU_TIMER_STATUS_PENDING        = 1u << 0,
};

#endif  /* OMCU_REGS_H_ */
