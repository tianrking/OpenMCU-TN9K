#ifndef OMCU_DEVICES_H_
#define OMCU_DEVICES_H_

/*
 * P0 drivers for common 3.3 V devices attached to SPI0/I2C0.  These APIs are
 * deliberately board-independent: power, pull-ups, chip-select wiring and
 * true on-target electrical verification remain the product's responsibility.
 */

#include "omcu_bus.h"

#include <stdbool.h>
#include <stdint.h>

#define OMCU_DS3231_DEFAULT_ADDRESS UINT8_C(0x68)
#define OMCU_TMP102_DEFAULT_ADDRESS UINT8_C(0x48)
#define OMCU_W5500_VERSION          UINT8_C(0x04)

typedef struct {
  uint8_t second;
  uint8_t minute;
  uint8_t hour;
  uint8_t weekday;
  uint8_t day;
  uint8_t month;
  uint16_t year;
} omcu_rtc_time_t;

bool omcu_ds3231_read_time(uint8_t address_7bit, omcu_rtc_time_t *time,
                           uint32_t spin_limit);
bool omcu_ds3231_write_time(uint8_t address_7bit,
                            const omcu_rtc_time_t *time,
                            uint32_t spin_limit);

bool omcu_at24cxx_read(uint8_t address_7bit, uint16_t memory_address,
                       uint8_t address_bytes, uint8_t *data,
                       uint32_t data_bytes, uint32_t spin_limit);
bool omcu_at24cxx_write(uint8_t address_7bit, uint16_t memory_address,
                        uint8_t address_bytes, uint8_t page_bytes,
                        const uint8_t *data, uint32_t data_bytes,
                        uint32_t ready_poll_attempts,
                        uint32_t spin_limit);

bool omcu_tmp102_read_temperature_milli_c(uint8_t address_7bit,
                                           int32_t *temperature_milli_c,
                                           uint32_t spin_limit);
bool omcu_mcp3008_read_channel(uint8_t channel, uint16_t *sample,
                               uint32_t spin_limit);
bool omcu_mcp4921_write(uint16_t value, bool buffered, bool gain_1x,
                        uint32_t spin_limit);

typedef struct {
  uint8_t gateway[4];
  uint8_t subnet[4];
  uint8_t mac[6];
  uint8_t ip[4];
} omcu_w5500_netinfo_t;

enum {
  OMCU_W5500_SOCKET_MODE_TCP = 0x01u,
  OMCU_W5500_SOCKET_MODE_UDP = 0x02u,
  OMCU_W5500_SOCKET_STATUS_CLOSED = 0x00u,
  OMCU_W5500_SOCKET_STATUS_INIT = 0x13u,
  OMCU_W5500_SOCKET_STATUS_UDP = 0x22u,
  OMCU_W5500_SOCKET_STATUS_ESTABLISHED = 0x17u,
};

/* block_select is the W5500 BSB field (0..31), not a pre-shifted control byte. */
bool omcu_w5500_read(uint16_t address, uint8_t block_select, uint8_t *data,
                     uint16_t data_bytes, uint32_t spin_limit);
bool omcu_w5500_write(uint16_t address, uint8_t block_select,
                      const uint8_t *data, uint16_t data_bytes,
                      uint32_t spin_limit);
bool omcu_w5500_initialize(const omcu_w5500_netinfo_t *netinfo,
                           uint8_t *version, uint32_t spin_limit);
bool omcu_w5500_socket_open(uint8_t socket, uint8_t mode, uint16_t local_port,
                            uint8_t buffer_kib, uint32_t spin_limit);
bool omcu_w5500_socket_connect(uint8_t socket, const uint8_t remote_ip[4],
                               uint16_t remote_port, uint32_t spin_limit);
bool omcu_w5500_socket_send(uint8_t socket, const uint8_t *data,
                            uint16_t data_bytes, uint16_t buffer_bytes,
                            uint32_t spin_limit);
uint16_t omcu_w5500_socket_receive(uint8_t socket, uint8_t *data,
                                    uint16_t data_capacity,
                                    uint16_t buffer_bytes,
                                    uint32_t spin_limit);

#endif  /* OMCU_DEVICES_H_ */
