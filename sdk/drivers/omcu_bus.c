#include "omcu_bus.h"

static bool omcu_spi0_wait_idle(uint32_t spin_limit) {
  while (spin_limit != 0u) {
    if ((OMCU_SPI0->status & OMCU_SPI_STATUS_BUSY) == 0u) {
      return true;
    }
    --spin_limit;
  }
  return false;
}

bool omcu_spi0_transfer_timeout(uint8_t tx, uint8_t *rx,
                                uint32_t spin_limit) {
  uint32_t status;

  if ((OMCU_SPI0->ctrl & OMCU_SPI_CTRL_ENABLE) == 0u ||
      !omcu_spi0_wait_idle(spin_limit)) {
    return false;
  }
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  OMCU_SPI0->data = tx;
  OMCU_SPI0->start = 1u;
  if (!omcu_spi0_wait_idle(spin_limit)) {
    return false;
  }
  status = OMCU_SPI0->status;
  if ((status & OMCU_SPI_STATUS_DONE) == 0u) {
    return false;
  }
  if (rx != 0) {
    *rx = (uint8_t)OMCU_SPI0->data;
  }
  OMCU_SPI0->status = OMCU_SPI_STATUS_DONE;
  return true;
}

bool omcu_spi0_frame_begin(uint32_t spin_limit) {
  if ((OMCU_SPI0->ctrl & OMCU_SPI_CTRL_ENABLE) == 0u ||
      !omcu_spi0_wait_idle(spin_limit)) {
    return false;
  }
  omcu_spi0_set_cs_hold(true);
  return true;
}

bool omcu_spi0_frame_transfer(uint8_t tx, uint8_t *rx,
                              uint32_t spin_limit) {
  return omcu_spi0_transfer_timeout(tx, rx, spin_limit);
}

void omcu_spi0_frame_end(void) {
  /* The SPI block releases CS when this is written after BUSY has gone low. */
  omcu_spi0_set_cs_hold(false);
}

static bool omcu_i2c0_wait_idle(uint32_t spin_limit) {
  while (spin_limit != 0u) {
    if ((OMCU_I2C0->status & OMCU_I2C_STATUS_BUSY) == 0u) {
      return true;
    }
    --spin_limit;
  }
  return false;
}

static bool omcu_i2c0_command_timeout(uint32_t command,
                                      uint32_t spin_limit) {
  const uint32_t terminal = OMCU_I2C_STATUS_DONE |
                            OMCU_I2C_STATUS_ACK_ERROR |
                            OMCU_I2C_STATUS_COMMAND_ERROR;
  bool busy_seen = false;

  if ((OMCU_I2C0->ctrl & OMCU_I2C_CTRL_ENABLE) == 0u ||
      !omcu_i2c0_wait_idle(spin_limit)) {
    return false;
  }
  OMCU_I2C0->status = terminal;
  OMCU_I2C0->cmd = command;
  while (spin_limit != 0u) {
    uint32_t status = OMCU_I2C0->status;

    if ((status & OMCU_I2C_STATUS_BUSY) != 0u) {
      busy_seen = true;
    }
    if ((status & terminal) != 0u) {
      return (status & terminal) == OMCU_I2C_STATUS_DONE;
    }
    if (busy_seen && (status & OMCU_I2C_STATUS_BUSY) == 0u) {
      return false;
    }
    --spin_limit;
  }
  return false;
}

static void omcu_i2c0_stop_ignore_failure(uint32_t spin_limit) {
  (void)omcu_i2c0_command_timeout(OMCU_I2C_CMD_STOP, spin_limit);
}

bool omcu_i2c0_write(uint8_t address_7bit, const uint8_t *data,
                     uint32_t data_bytes, uint32_t spin_limit) {
  uint32_t index;

  if (address_7bit > 0x7fu || (data_bytes != 0u && data == 0)) {
    return false;
  }
  if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_START, spin_limit)) {
    return false;
  }
  OMCU_I2C0->data = (uint32_t)address_7bit << 1u;
  if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_WRITE, spin_limit)) {
    omcu_i2c0_stop_ignore_failure(spin_limit);
    return false;
  }
  for (index = 0u; index < data_bytes; ++index) {
    OMCU_I2C0->data = data[index];
    if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_WRITE, spin_limit)) {
      omcu_i2c0_stop_ignore_failure(spin_limit);
      return false;
    }
  }
  return omcu_i2c0_command_timeout(OMCU_I2C_CMD_STOP, spin_limit);
}

bool omcu_i2c0_read(uint8_t address_7bit, uint8_t *data,
                    uint32_t data_bytes, uint32_t spin_limit) {
  uint32_t index;

  if (address_7bit > 0x7fu || data == 0 || data_bytes == 0u) {
    return false;
  }
  if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_START, spin_limit)) {
    return false;
  }
  OMCU_I2C0->data = ((uint32_t)address_7bit << 1u) | 1u;
  if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_WRITE, spin_limit)) {
    omcu_i2c0_stop_ignore_failure(spin_limit);
    return false;
  }
  for (index = 0u; index < data_bytes; ++index) {
    uint32_t command = (index + 1u == data_bytes)
      ? OMCU_I2C_CMD_READ_NACK : OMCU_I2C_CMD_READ_ACK;
    if (!omcu_i2c0_command_timeout(command, spin_limit)) {
      omcu_i2c0_stop_ignore_failure(spin_limit);
      return false;
    }
    data[index] = (uint8_t)OMCU_I2C0->data;
  }
  return omcu_i2c0_command_timeout(OMCU_I2C_CMD_STOP, spin_limit);
}

bool omcu_i2c0_write_read(uint8_t address_7bit,
                          const uint8_t *write_data,
                          uint32_t write_bytes,
                          uint8_t *read_data,
                          uint32_t read_bytes,
                          uint32_t spin_limit) {
  uint32_t index;

  if (address_7bit > 0x7fu ||
      (write_bytes != 0u && write_data == 0) ||
      (read_bytes != 0u && read_data == 0) ||
      read_bytes == 0u) {
    return false;
  }
  if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_START, spin_limit)) {
    return false;
  }
  if (write_bytes != 0u) {
    OMCU_I2C0->data = (uint32_t)address_7bit << 1u;
    if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_WRITE, spin_limit)) {
      omcu_i2c0_stop_ignore_failure(spin_limit);
      return false;
    }
    for (index = 0u; index < write_bytes; ++index) {
      OMCU_I2C0->data = write_data[index];
      if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_WRITE, spin_limit)) {
        omcu_i2c0_stop_ignore_failure(spin_limit);
        return false;
      }
    }
    if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_START, spin_limit)) {
      omcu_i2c0_stop_ignore_failure(spin_limit);
      return false;
    }
  }
  OMCU_I2C0->data = ((uint32_t)address_7bit << 1u) | 1u;
  if (!omcu_i2c0_command_timeout(OMCU_I2C_CMD_WRITE, spin_limit)) {
    omcu_i2c0_stop_ignore_failure(spin_limit);
    return false;
  }
  for (index = 0u; index < read_bytes; ++index) {
    uint32_t command = (index + 1u == read_bytes)
      ? OMCU_I2C_CMD_READ_NACK : OMCU_I2C_CMD_READ_ACK;
    if (!omcu_i2c0_command_timeout(command, spin_limit)) {
      omcu_i2c0_stop_ignore_failure(spin_limit);
      return false;
    }
    read_data[index] = (uint8_t)OMCU_I2C0->data;
  }
  return omcu_i2c0_command_timeout(OMCU_I2C_CMD_STOP, spin_limit);
}
