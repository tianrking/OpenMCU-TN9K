#include "omcu_devices.h"

static bool omcu_bcd_to_decimal(uint8_t bcd, uint8_t maximum, uint8_t *value) {
  uint8_t tens = (uint8_t)((bcd >> 4u) & 0x0fu);
  uint8_t units = (uint8_t)(bcd & 0x0fu);
  uint8_t decoded;

  if (tens > 9u || units > 9u) {
    return false;
  }
  decoded = (uint8_t)(tens * 10u + units);
  if (decoded > maximum) {
    return false;
  }
  *value = decoded;
  return true;
}

static uint8_t omcu_decimal_to_bcd(uint8_t value) {
  return (uint8_t)(((value / 10u) << 4u) | (value % 10u));
}

bool omcu_ds3231_read_time(uint8_t address_7bit, omcu_rtc_time_t *time,
                           uint32_t spin_limit) {
  const uint8_t register_address = 0x00u;
  uint8_t bytes[7];
  uint8_t hour;
  uint8_t month;

  if (time == 0 || !omcu_i2c0_write_read(address_7bit, &register_address,
                                          1u, bytes, 7u, spin_limit) ||
      !omcu_bcd_to_decimal((uint8_t)(bytes[0] & 0x7fu), 59u, &time->second) ||
      !omcu_bcd_to_decimal((uint8_t)(bytes[1] & 0x7fu), 59u, &time->minute) ||
      !omcu_bcd_to_decimal((uint8_t)(bytes[3] & 0x3fu), 31u, &time->day) ||
      !omcu_bcd_to_decimal((uint8_t)(bytes[5] & 0x1fu), 12u, &month) ||
      !omcu_bcd_to_decimal(bytes[6], 99u, &hour) ||
      bytes[2] == 0xffu || bytes[4] == 0u || bytes[4] > 7u) {
    return false;
  }
  if ((bytes[2] & 0x40u) != 0u) {
    uint8_t hour12;
    if (!omcu_bcd_to_decimal((uint8_t)(bytes[2] & 0x1fu), 12u, &hour12) ||
        hour12 == 0u) {
      return false;
    }
    hour = (uint8_t)(hour12 % 12u);
    if ((bytes[2] & 0x20u) != 0u) {
      hour = (uint8_t)(hour + 12u);
    }
  } else if (!omcu_bcd_to_decimal((uint8_t)(bytes[2] & 0x3fu), 23u, &hour)) {
    return false;
  }
  time->hour = hour;
  time->weekday = bytes[4];
  time->month = month;
  time->year = (uint16_t)(2000u + (uint16_t)((bytes[6] >> 4u) * 10u +
                                              (bytes[6] & 0x0fu)));
  return true;
}

bool omcu_ds3231_write_time(uint8_t address_7bit,
                            const omcu_rtc_time_t *time,
                            uint32_t spin_limit) {
  uint8_t frame[8];

  if (time == 0 || time->second > 59u || time->minute > 59u ||
      time->hour > 23u || time->weekday == 0u || time->weekday > 7u ||
      time->day == 0u || time->day > 31u || time->month == 0u ||
      time->month > 12u || time->year < 2000u || time->year > 2099u) {
    return false;
  }
  frame[0] = 0x00u;
  frame[1] = omcu_decimal_to_bcd(time->second);
  frame[2] = omcu_decimal_to_bcd(time->minute);
  frame[3] = omcu_decimal_to_bcd(time->hour);
  frame[4] = time->weekday;
  frame[5] = omcu_decimal_to_bcd(time->day);
  frame[6] = omcu_decimal_to_bcd(time->month);
  frame[7] = omcu_decimal_to_bcd((uint8_t)(time->year - 2000u));
  return omcu_i2c0_write(address_7bit, frame, 8u, spin_limit);
}

static bool omcu_at24cxx_make_address(uint16_t memory_address,
                                      uint8_t address_bytes,
                                      uint8_t bytes[2]) {
  if (address_bytes == 1u) {
    if (memory_address > 0xffu) {
      return false;
    }
    bytes[0] = (uint8_t)memory_address;
    return true;
  }
  if (address_bytes == 2u) {
    bytes[0] = (uint8_t)(memory_address >> 8u);
    bytes[1] = (uint8_t)memory_address;
    return true;
  }
  return false;
}

bool omcu_at24cxx_read(uint8_t address_7bit, uint16_t memory_address,
                       uint8_t address_bytes, uint8_t *data,
                       uint32_t data_bytes, uint32_t spin_limit) {
  uint8_t address_frame[2];

  if (data == 0 || data_bytes == 0u ||
      !omcu_at24cxx_make_address(memory_address, address_bytes,
                                 address_frame)) {
    return false;
  }
  return omcu_i2c0_write_read(address_7bit, address_frame, address_bytes,
                               data, data_bytes, spin_limit);
}

bool omcu_at24cxx_write(uint8_t address_7bit, uint16_t memory_address,
                        uint8_t address_bytes, uint8_t page_bytes,
                        const uint8_t *data, uint32_t data_bytes,
                        uint32_t ready_poll_attempts,
                        uint32_t spin_limit) {
  uint32_t written = 0u;

  /* The bounded 32-byte staging frame keeps this driver allocation-free. */
  if (data == 0 || data_bytes == 0u || page_bytes == 0u || page_bytes > 32u ||
      ready_poll_attempts == 0u ||
      data_bytes > UINT32_C(0x10000) - (uint32_t)memory_address ||
      (address_bytes != 1u && address_bytes != 2u)) {
    return false;
  }
  while (written < data_bytes) {
    uint8_t frame[34];
    uint16_t current_address = (uint16_t)((uint32_t)memory_address + written);
    uint32_t page_offset = (uint32_t)current_address % page_bytes;
    uint32_t chunk = page_bytes - page_offset;
    uint32_t index;
    bool ready = false;

    if (chunk > data_bytes - written) {
      chunk = data_bytes - written;
    }
    if (!omcu_at24cxx_make_address(current_address, address_bytes, frame)) {
      return false;
    }
    for (index = 0u; index < chunk; ++index) {
      frame[address_bytes + index] = data[written + index];
    }
    if (!omcu_i2c0_write(address_7bit, frame, address_bytes + chunk,
                         spin_limit)) {
      return false;
    }
    for (index = 0u; index < ready_poll_attempts; ++index) {
      if (omcu_i2c0_write(address_7bit, 0, 0u, spin_limit)) {
        ready = true;
        break;
      }
    }
    if (!ready) {
      return false;
    }
    written += chunk;
  }
  return true;
}

bool omcu_tmp102_read_temperature_milli_c(uint8_t address_7bit,
                                           int32_t *temperature_milli_c,
                                           uint32_t spin_limit) {
  const uint8_t register_address = 0x00u;
  uint8_t bytes[2];
  int32_t raw;

  if (temperature_milli_c == 0 ||
      !omcu_i2c0_write_read(address_7bit, &register_address, 1u,
                             bytes, 2u, spin_limit)) {
    return false;
  }
  raw = (int32_t)(((uint16_t)bytes[0] << 4u) | (bytes[1] >> 4u));
  if ((raw & 0x800) != 0) {
    raw -= 0x1000;
  }
  *temperature_milli_c = (raw * 625) / 10;
  return true;
}

bool omcu_mcp3008_read_channel(uint8_t channel, uint16_t *sample,
                               uint32_t spin_limit) {
  uint8_t rx0;
  uint8_t rx1;
  uint8_t rx2;
  bool ok;

  if (channel > 7u || sample == 0 || !omcu_spi0_frame_begin(spin_limit)) {
    return false;
  }
  ok = omcu_spi0_frame_transfer(0x01u, &rx0, spin_limit) &&
       omcu_spi0_frame_transfer((uint8_t)(0x80u | (channel << 4u)), &rx1,
                                spin_limit) &&
       omcu_spi0_frame_transfer(0x00u, &rx2, spin_limit);
  omcu_spi0_frame_end();
  if (!ok) {
    return false;
  }
  *sample = (uint16_t)(((uint16_t)(rx1 & 0x03u) << 8u) | rx2);
  return true;
}

bool omcu_mcp4921_write(uint16_t value, bool buffered, bool gain_1x,
                        uint32_t spin_limit) {
  uint16_t frame;
  bool ok;

  if (value > 0x0fffu || !omcu_spi0_frame_begin(spin_limit)) {
    return false;
  }
  frame = (uint16_t)(0x1000u | value);
  if (buffered) {
    frame |= 0x4000u;
  }
  if (gain_1x) {
    frame |= 0x2000u;
  }
  ok = omcu_spi0_frame_transfer((uint8_t)(frame >> 8u), 0, spin_limit) &&
       omcu_spi0_frame_transfer((uint8_t)frame, 0, spin_limit);
  omcu_spi0_frame_end();
  return ok;
}

enum {
  OMCU_W5500_COMMON_BLOCK = 0u,
  OMCU_W5500_COMMON_MR = 0x0000u,
  OMCU_W5500_COMMON_GAR = 0x0001u,
  OMCU_W5500_COMMON_SUBR = 0x0005u,
  OMCU_W5500_COMMON_SHAR = 0x0009u,
  OMCU_W5500_COMMON_SIPR = 0x000fu,
  OMCU_W5500_COMMON_VERSIONR = 0x0039u,
  OMCU_W5500_SOCKET_MR = 0x0000u,
  OMCU_W5500_SOCKET_CR = 0x0001u,
  OMCU_W5500_SOCKET_IR = 0x0002u,
  OMCU_W5500_SOCKET_SR = 0x0003u,
  OMCU_W5500_SOCKET_PORT = 0x0004u,
  OMCU_W5500_SOCKET_DIPR = 0x000cu,
  OMCU_W5500_SOCKET_DPORT = 0x0010u,
  OMCU_W5500_SOCKET_TX_FSR = 0x0020u,
  OMCU_W5500_SOCKET_TX_WR = 0x0024u,
  OMCU_W5500_SOCKET_RX_RSR = 0x0026u,
  OMCU_W5500_SOCKET_RX_RD = 0x0028u,
  OMCU_W5500_SOCKET_RXBUF_SIZE = 0x001eu,
  OMCU_W5500_SOCKET_TXBUF_SIZE = 0x001fu,
  OMCU_W5500_SOCKET_COMMAND_OPEN = 0x01u,
  OMCU_W5500_SOCKET_COMMAND_CONNECT = 0x04u,
  OMCU_W5500_SOCKET_COMMAND_DISCONNECT = 0x08u,
  OMCU_W5500_SOCKET_COMMAND_CLOSE = 0x10u,
  OMCU_W5500_SOCKET_COMMAND_SEND = 0x20u,
  OMCU_W5500_SOCKET_COMMAND_RECV = 0x40u,
  OMCU_W5500_SOCKET_IR_SENDOK = 0x10u,
  OMCU_W5500_SOCKET_IR_TIMEOUT = 0x08u,
};

static bool omcu_w5500_valid_socket(uint8_t socket) {
  return socket < 8u;
}

static uint8_t omcu_w5500_socket_reg_block(uint8_t socket) {
  return (uint8_t)(1u + 4u * socket);
}

static uint8_t omcu_w5500_socket_tx_block(uint8_t socket) {
  return (uint8_t)(2u + 4u * socket);
}

static uint8_t omcu_w5500_socket_rx_block(uint8_t socket) {
  return (uint8_t)(3u + 4u * socket);
}

static bool omcu_w5500_transfer(uint16_t address, uint8_t block_select,
                                 bool read, uint8_t *read_data,
                                 const uint8_t *write_data,
                                 uint16_t data_bytes,
                                 uint32_t spin_limit) {
  uint16_t index;
  uint8_t discard;
  bool ok;

  if (block_select > 31u ||
      (read && data_bytes != 0u && read_data == 0) ||
      (!read && data_bytes != 0u && write_data == 0) ||
      !omcu_spi0_frame_begin(spin_limit)) {
    return false;
  }
  ok = omcu_spi0_frame_transfer((uint8_t)(address >> 8u), &discard,
                                spin_limit) &&
       omcu_spi0_frame_transfer((uint8_t)address, &discard, spin_limit) &&
       omcu_spi0_frame_transfer((uint8_t)((block_select << 3u) |
                                          (read ? 0x04u : 0x00u)),
                                &discard, spin_limit);
  for (index = 0u; ok && index < data_bytes; ++index) {
    if (read) {
      ok = omcu_spi0_frame_transfer(0x00u, &read_data[index], spin_limit);
    } else {
      ok = omcu_spi0_frame_transfer(write_data[index], &discard, spin_limit);
    }
  }
  omcu_spi0_frame_end();
  return ok;
}

bool omcu_w5500_read(uint16_t address, uint8_t block_select, uint8_t *data,
                     uint16_t data_bytes, uint32_t spin_limit) {
  return omcu_w5500_transfer(address, block_select, true, data, 0,
                             data_bytes, spin_limit);
}

bool omcu_w5500_write(uint16_t address, uint8_t block_select,
                      const uint8_t *data, uint16_t data_bytes,
                      uint32_t spin_limit) {
  return omcu_w5500_transfer(address, block_select, false, 0, data,
                             data_bytes, spin_limit);
}

static bool omcu_w5500_read_u16(uint16_t address, uint8_t block_select,
                                 uint16_t *value, uint32_t spin_limit) {
  uint8_t bytes[2];

  if (value == 0 || !omcu_w5500_read(address, block_select, bytes, 2u,
                                      spin_limit)) {
    return false;
  }
  *value = (uint16_t)((uint16_t)bytes[0] << 8u) | bytes[1];
  return true;
}

static bool omcu_w5500_write_u16(uint16_t address, uint8_t block_select,
                                  uint16_t value, uint32_t spin_limit) {
  uint8_t bytes[2];

  bytes[0] = (uint8_t)(value >> 8u);
  bytes[1] = (uint8_t)value;
  return omcu_w5500_write(address, block_select, bytes, 2u, spin_limit);
}

static bool omcu_w5500_socket_command(uint8_t socket, uint8_t command,
                                      uint32_t spin_limit) {
  uint8_t block;
  uint8_t value;
  uint32_t attempts;

  if (!omcu_w5500_valid_socket(socket)) {
    return false;
  }
  block = omcu_w5500_socket_reg_block(socket);
  if (!omcu_w5500_write(OMCU_W5500_SOCKET_CR, block, &command, 1u,
                        spin_limit)) {
    return false;
  }
  attempts = spin_limit < 1024u ? spin_limit : 1024u;
  while (attempts != 0u) {
    if (!omcu_w5500_read(OMCU_W5500_SOCKET_CR, block, &value, 1u,
                          spin_limit)) {
      return false;
    }
    if (value == 0u) {
      return true;
    }
    --attempts;
  }
  return false;
}

bool omcu_w5500_initialize(const omcu_w5500_netinfo_t *netinfo,
                           uint8_t *version, uint32_t spin_limit) {
  uint8_t reset = 0x80u;
  uint8_t mr;
  uint32_t attempts;

  if (netinfo == 0 || !omcu_w5500_write(OMCU_W5500_COMMON_MR,
                                         OMCU_W5500_COMMON_BLOCK,
                                         &reset, 1u, spin_limit)) {
    return false;
  }
  attempts = spin_limit < 1024u ? spin_limit : 1024u;
  do {
    if (!omcu_w5500_read(OMCU_W5500_COMMON_MR, OMCU_W5500_COMMON_BLOCK,
                          &mr, 1u, spin_limit)) {
      return false;
    }
    if ((mr & 0x80u) == 0u) {
      break;
    }
    --attempts;
  } while (attempts != 0u);
  if ((mr & 0x80u) != 0u ||
      !omcu_w5500_write(OMCU_W5500_COMMON_GAR, OMCU_W5500_COMMON_BLOCK,
                         netinfo->gateway, 4u, spin_limit) ||
      !omcu_w5500_write(OMCU_W5500_COMMON_SUBR, OMCU_W5500_COMMON_BLOCK,
                         netinfo->subnet, 4u, spin_limit) ||
      !omcu_w5500_write(OMCU_W5500_COMMON_SHAR, OMCU_W5500_COMMON_BLOCK,
                         netinfo->mac, 6u, spin_limit) ||
      !omcu_w5500_write(OMCU_W5500_COMMON_SIPR, OMCU_W5500_COMMON_BLOCK,
                         netinfo->ip, 4u, spin_limit)) {
    return false;
  }
  if (version != 0) {
    if (!omcu_w5500_read(OMCU_W5500_COMMON_VERSIONR,
                          OMCU_W5500_COMMON_BLOCK, version, 1u,
                          spin_limit)) {
      return false;
    }
    return *version == OMCU_W5500_VERSION;
  }
  return true;
}

bool omcu_w5500_socket_open(uint8_t socket, uint8_t mode, uint16_t local_port,
                            uint8_t buffer_kib, uint32_t spin_limit) {
  uint8_t block;
  uint8_t sizes[2];
  uint8_t status;

  if (!omcu_w5500_valid_socket(socket) ||
      (mode != OMCU_W5500_SOCKET_MODE_TCP &&
       mode != OMCU_W5500_SOCKET_MODE_UDP) ||
      (buffer_kib != 1u && buffer_kib != 2u && buffer_kib != 4u &&
       buffer_kib != 8u && buffer_kib != 16u)) {
    return false;
  }
  block = omcu_w5500_socket_reg_block(socket);
  if (!omcu_w5500_socket_command(socket, OMCU_W5500_SOCKET_COMMAND_CLOSE,
                                 spin_limit)) {
    return false;
  }
  sizes[0] = buffer_kib;
  sizes[1] = buffer_kib;
  if (!omcu_w5500_write(OMCU_W5500_SOCKET_RXBUF_SIZE, block, sizes, 2u,
                         spin_limit) ||
      !omcu_w5500_write(OMCU_W5500_SOCKET_MR, block, &mode, 1u, spin_limit) ||
      !omcu_w5500_write_u16(OMCU_W5500_SOCKET_PORT, block, local_port,
                             spin_limit) ||
      !omcu_w5500_socket_command(socket, OMCU_W5500_SOCKET_COMMAND_OPEN,
                                 spin_limit) ||
      !omcu_w5500_read(OMCU_W5500_SOCKET_SR, block, &status, 1u,
                        spin_limit)) {
    return false;
  }
  return mode == OMCU_W5500_SOCKET_MODE_TCP
    ? status == OMCU_W5500_SOCKET_STATUS_INIT
    : status == OMCU_W5500_SOCKET_STATUS_UDP;
}

bool omcu_w5500_socket_connect(uint8_t socket, const uint8_t remote_ip[4],
                               uint16_t remote_port, uint32_t spin_limit) {
  uint8_t block;

  if (!omcu_w5500_valid_socket(socket) || remote_ip == 0) {
    return false;
  }
  block = omcu_w5500_socket_reg_block(socket);
  return omcu_w5500_write(OMCU_W5500_SOCKET_DIPR, block, remote_ip, 4u,
                           spin_limit) &&
         omcu_w5500_write_u16(OMCU_W5500_SOCKET_DPORT, block, remote_port,
                               spin_limit) &&
         omcu_w5500_socket_command(socket,
                                   OMCU_W5500_SOCKET_COMMAND_CONNECT,
                                   spin_limit);
}

static bool omcu_w5500_ring_write(uint8_t block, uint16_t pointer,
                                  const uint8_t *data, uint16_t data_bytes,
                                  uint16_t buffer_bytes,
                                  uint32_t spin_limit) {
  uint16_t offset = (uint16_t)(pointer % buffer_bytes);
  uint16_t first = (uint16_t)(buffer_bytes - offset);

  if (first > data_bytes) {
    first = data_bytes;
  }
  return omcu_w5500_write(offset, block, data, first, spin_limit) &&
         (first == data_bytes ||
          omcu_w5500_write(0u, block, &data[first],
                            (uint16_t)(data_bytes - first), spin_limit));
}

static bool omcu_w5500_ring_read(uint8_t block, uint16_t pointer,
                                 uint8_t *data, uint16_t data_bytes,
                                 uint16_t buffer_bytes,
                                 uint32_t spin_limit) {
  uint16_t offset = (uint16_t)(pointer % buffer_bytes);
  uint16_t first = (uint16_t)(buffer_bytes - offset);

  if (first > data_bytes) {
    first = data_bytes;
  }
  return omcu_w5500_read(offset, block, data, first, spin_limit) &&
         (first == data_bytes ||
          omcu_w5500_read(0u, block, &data[first],
                           (uint16_t)(data_bytes - first), spin_limit));
}

bool omcu_w5500_socket_send(uint8_t socket, const uint8_t *data,
                            uint16_t data_bytes, uint16_t buffer_bytes,
                            uint32_t spin_limit) {
  uint8_t block;
  uint8_t ir;
  uint16_t free_bytes;
  uint16_t write_pointer;
  uint32_t attempts;

  if (!omcu_w5500_valid_socket(socket) || data == 0 || data_bytes == 0u ||
      buffer_bytes == 0u || data_bytes > buffer_bytes) {
    return false;
  }
  block = omcu_w5500_socket_reg_block(socket);
  if (!omcu_w5500_read_u16(OMCU_W5500_SOCKET_TX_FSR, block, &free_bytes,
                            spin_limit) || free_bytes < data_bytes ||
      !omcu_w5500_read_u16(OMCU_W5500_SOCKET_TX_WR, block, &write_pointer,
                            spin_limit) ||
      !omcu_w5500_ring_write(omcu_w5500_socket_tx_block(socket), write_pointer,
                             data, data_bytes, buffer_bytes, spin_limit) ||
      !omcu_w5500_write_u16(OMCU_W5500_SOCKET_TX_WR, block,
                             (uint16_t)(write_pointer + data_bytes),
                             spin_limit) ||
      !omcu_w5500_socket_command(socket, OMCU_W5500_SOCKET_COMMAND_SEND,
                                 spin_limit)) {
    return false;
  }
  attempts = spin_limit < 4096u ? spin_limit : 4096u;
  while (attempts != 0u) {
    if (!omcu_w5500_read(OMCU_W5500_SOCKET_IR, block, &ir, 1u,
                          spin_limit)) {
      return false;
    }
    if ((ir & (OMCU_W5500_SOCKET_IR_SENDOK |
               OMCU_W5500_SOCKET_IR_TIMEOUT)) != 0u) {
      (void)omcu_w5500_write(OMCU_W5500_SOCKET_IR, block, &ir, 1u,
                              spin_limit);
      return (ir & OMCU_W5500_SOCKET_IR_SENDOK) != 0u;
    }
    --attempts;
  }
  return false;
}

uint16_t omcu_w5500_socket_receive(uint8_t socket, uint8_t *data,
                                    uint16_t data_capacity,
                                    uint16_t buffer_bytes,
                                    uint32_t spin_limit) {
  uint8_t block;
  uint16_t received_bytes;
  uint16_t read_pointer;
  uint16_t copied;

  if (!omcu_w5500_valid_socket(socket) || data == 0 || data_capacity == 0u ||
      buffer_bytes == 0u) {
    return 0u;
  }
  block = omcu_w5500_socket_reg_block(socket);
  if (!omcu_w5500_read_u16(OMCU_W5500_SOCKET_RX_RSR, block, &received_bytes,
                            spin_limit) || received_bytes == 0u ||
      !omcu_w5500_read_u16(OMCU_W5500_SOCKET_RX_RD, block, &read_pointer,
                            spin_limit)) {
    return 0u;
  }
  copied = received_bytes < data_capacity ? received_bytes : data_capacity;
  if (!omcu_w5500_ring_read(omcu_w5500_socket_rx_block(socket), read_pointer,
                            data, copied, buffer_bytes, spin_limit) ||
      !omcu_w5500_write_u16(OMCU_W5500_SOCKET_RX_RD, block,
                             (uint16_t)(read_pointer + copied), spin_limit) ||
      !omcu_w5500_socket_command(socket, OMCU_W5500_SOCKET_COMMAND_RECV,
                                 spin_limit)) {
    return 0u;
  }
  return copied;
}
