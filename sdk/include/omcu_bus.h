#ifndef OMCU_BUS_H_
#define OMCU_BUS_H_

/*
 * Bounded, transaction-level helpers for the OpenMCU byte-at-a-time SPI0 and
 * I2C0 engines.  They intentionally allocate no FIFO or dynamic memory: the
 * caller owns all data buffers and every wait has an explicit spin budget.
 */

#include "omcu.h"

#include <stdbool.h>
#include <stdint.h>

enum {
  /* Suitable for a short 100 kHz I2C transaction at a 27 MHz system clock. */
  OMCU_BUS_DEFAULT_SPIN_LIMIT = 1000000u,
};

bool omcu_spi0_transfer_timeout(uint8_t tx, uint8_t *rx,
                                uint32_t spin_limit);
bool omcu_spi0_frame_begin(uint32_t spin_limit);
bool omcu_spi0_frame_transfer(uint8_t tx, uint8_t *rx,
                              uint32_t spin_limit);
void omcu_spi0_frame_end(void);

bool omcu_i2c0_write(uint8_t address_7bit, const uint8_t *data,
                     uint32_t data_bytes, uint32_t spin_limit);
bool omcu_i2c0_read(uint8_t address_7bit, uint8_t *data,
                    uint32_t data_bytes, uint32_t spin_limit);
bool omcu_i2c0_write_read(uint8_t address_7bit,
                          const uint8_t *write_data,
                          uint32_t write_bytes,
                          uint8_t *read_data,
                          uint32_t read_bytes,
                          uint32_t spin_limit);

#endif  /* OMCU_BUS_H_ */
