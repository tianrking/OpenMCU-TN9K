#ifndef OMCU_REGS_H_
#define OMCU_REGS_H_

/*
 * Generated from spec/omcu-v0.json by scripts/generate-sdk.ps1.
 * Do not hand-edit this file; change the reviewed specification instead.
 */

#include <stdint.h>

#define OMCU_ROM_BASE            UINT32_C(0x00000000)
#define OMCU_SRAM_BASE           UINT32_C(0x10000000)
#define OMCU_USER_FLASH_BASE     UINT32_C(0x20000000)
#define OMCU_QSPI_XIP_BASE       UINT32_C(0x20000000)
#define OMCU_GPIO0_BASE          UINT32_C(0x40000000)
#define OMCU_UART0_BASE          UINT32_C(0x40001000)
#define OMCU_TIMER0_BASE         UINT32_C(0x40002000)
#define OMCU_SPI0_BASE           UINT32_C(0x40003000)
#define OMCU_I2C0_BASE           UINT32_C(0x40004000)
#define OMCU_WDT0_BASE           UINT32_C(0x40005000)
#define OMCU_PWM0_BASE           UINT32_C(0x40006000)
#define OMCU_IRQCTRL_BASE        UINT32_C(0x40007000)
#define OMCU_SYSCTRL_BASE        UINT32_C(0x4000F000)

#define OMCU_HW_ABI_MAJOR      0u
#define OMCU_HW_ABI_MINOR      5u

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
  volatile uint32_t data; /* +0x00: TX byte write / RX byte read */
  volatile uint32_t status; /* +0x04: BUSY and DONE, DONE is write-one-to-clear */
  volatile uint32_t clkdiv; /* +0x08: SCK half-period in system clocks minus one */
  volatile uint32_t ctrl; /* +0x0c: ENABLE and DONE interrupt enable */
  volatile uint32_t start; /* +0x10: write one to start one automatic mode-0 byte transfer */
} omcu_spi_regs_t;

typedef struct {
  volatile uint32_t data; /* +0x00: TX byte write / RX byte read */
  volatile uint32_t status; /* +0x04: BUSY, DONE W1C, ACK_ERROR W1C, COMMAND_ERROR W1C and BUS_ACTIVE */
  volatile uint32_t clkdiv; /* +0x08: SCL low/high phase in system clocks minus one */
  volatile uint32_t ctrl; /* +0x0c: ENABLE and DONE interrupt enable */
  volatile uint32_t cmd; /* +0x10: write exactly one command bit: START, STOP, WRITE, READ_ACK or READ_NACK */
} omcu_i2c_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: ENABLE, RESET_ENABLE and EXPIRED interrupt enable */
  volatile uint32_t timeout; /* +0x04: watchdog count limit before expiry */
  volatile uint32_t feed; /* +0x08: write OMCU_WDT_FEED_MAGIC to restart the watchdog count */
  volatile uint32_t status; /* +0x0c: EXPIRED is write-one-to-clear; RESET_REQUEST reports an active pulse */
} omcu_wdt_regs_t;

typedef struct {
  volatile uint32_t ctrl; /* +0x00: ENABLE and INVERT */
  volatile uint32_t prescale; /* +0x04: PWM counter clocks minus one */
  volatile uint32_t period; /* +0x08: inclusive PWM counter top */
  volatile uint32_t duty; /* +0x0c: output high while COUNT is strictly lower than DUTY */
  volatile const uint32_t count; /* +0x10: current PWM counter */
} omcu_pwm_regs_t;

typedef struct {
  volatile const uint32_t pending; /* +0x00: sticky and current source bits in CPU IRQ positions */
  volatile uint32_t enable; /* +0x04: per-source IRQ enable mask in CPU IRQ positions */
  volatile uint32_t clear; /* +0x08: write-one-to-clear sticky and software-pending source bits */
  volatile uint32_t force; /* +0x0c: write-one-to-set software-pending source bits */
  volatile const uint32_t active; /* +0x10: enabled pending source bits sent to the CPU */
  volatile const uint32_t highest; /* +0x14: lowest numbered active CPU IRQ bit, zero when none */
} omcu_irqctrl_regs_t;

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
#define OMCU_SPI0                ((omcu_spi_regs_t *)(uintptr_t)OMCU_SPI0_BASE)
#define OMCU_I2C0                ((omcu_i2c_regs_t *)(uintptr_t)OMCU_I2C0_BASE)
#define OMCU_WDT0                ((omcu_wdt_regs_t *)(uintptr_t)OMCU_WDT0_BASE)
#define OMCU_PWM0                ((omcu_pwm_regs_t *)(uintptr_t)OMCU_PWM0_BASE)
#define OMCU_IRQCTRL             ((omcu_irqctrl_regs_t *)(uintptr_t)OMCU_IRQCTRL_BASE)
#define OMCU_SYSCTRL             ((omcu_sysctrl_regs_t *)(uintptr_t)OMCU_SYSCTRL_BASE)

enum {
  OMCU_FEATURE_GPIO0               = 1u << 0,
  OMCU_FEATURE_UART0               = 1u << 1,
  OMCU_FEATURE_TIMER0              = 1u << 2,
  OMCU_FEATURE_SPI0                = 1u << 3,
  OMCU_FEATURE_I2C0                = 1u << 4,
  OMCU_FEATURE_WDT0                = 1u << 5,
  OMCU_FEATURE_PWM0                = 1u << 6,
  OMCU_FEATURE_IRQCTRL             = 1u << 7,
  OMCU_FEATURE_USER_FLASH          = 1u << 14,
  OMCU_IRQ_GPIO0                   = 1u << 8,
  OMCU_IRQ_UART0                   = 1u << 9,
  OMCU_IRQ_TIMER0                  = 1u << 10,
  OMCU_IRQ_SPI0                    = 1u << 11,
  OMCU_IRQ_I2C0                    = 1u << 12,
  OMCU_IRQ_WDT0                    = 1u << 13,
  OMCU_IRQ_EXTERNAL_MASK           = UINT32_C(0x00003F00),
  OMCU_TIMER_CTRL_ENABLE           = 1u << 0,
  OMCU_TIMER_CTRL_IRQ_ENABLE       = 1u << 1,
  OMCU_TIMER_CTRL_AUTO_RELOAD      = 1u << 2,
  OMCU_TIMER_STATUS_PENDING        = 1u << 0,
  OMCU_SPI_CTRL_ENABLE             = 1u << 0,
  OMCU_SPI_CTRL_IRQ_ENABLE         = 1u << 1,
  OMCU_SPI_STATUS_BUSY             = 1u << 0,
  OMCU_SPI_STATUS_DONE             = 1u << 1,
  OMCU_I2C_CTRL_ENABLE             = 1u << 0,
  OMCU_I2C_CTRL_IRQ_ENABLE         = 1u << 1,
  OMCU_I2C_STATUS_BUSY             = 1u << 0,
  OMCU_I2C_STATUS_DONE             = 1u << 1,
  OMCU_I2C_STATUS_ACK_ERROR        = 1u << 2,
  OMCU_I2C_STATUS_COMMAND_ERROR    = 1u << 3,
  OMCU_I2C_STATUS_BUS_ACTIVE       = 1u << 4,
  OMCU_I2C_CMD_START               = 1u << 0,
  OMCU_I2C_CMD_STOP                = 1u << 1,
  OMCU_I2C_CMD_WRITE               = 1u << 2,
  OMCU_I2C_CMD_READ_ACK            = 1u << 3,
  OMCU_I2C_CMD_READ_NACK           = 1u << 4,
  OMCU_WDT_CTRL_ENABLE             = 1u << 0,
  OMCU_WDT_CTRL_RESET_ENABLE       = 1u << 1,
  OMCU_WDT_CTRL_IRQ_ENABLE         = 1u << 2,
  OMCU_WDT_STATUS_EXPIRED          = 1u << 0,
  OMCU_WDT_FEED_MAGIC              = UINT32_C(0x51F15EED),
  OMCU_PWM_CTRL_ENABLE             = 1u << 0,
  OMCU_PWM_CTRL_INVERT             = 1u << 1,
};

#endif  /* OMCU_REGS_H_ */
