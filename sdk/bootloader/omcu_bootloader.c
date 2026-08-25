#include "omcu.h"
#include "omcu_image.h"
#include "omcu_tn9k.h"

#include <stdbool.h>
#include <stdint.h>

/* UART framing is deliberately stop-and-wait: User Flash page erase can take
 * roughly 120 ms, so the host never sends a second data packet until the
 * loader has acknowledged the first one. */
#define OMCU_BOOT_SOF0                 0xA5u
#define OMCU_BOOT_SOF1                 0x5Au
#define OMCU_BOOT_PROTOCOL_VERSION     1u
#define OMCU_BOOT_FRAME_MAX_PAYLOAD    128u
#define OMCU_BOOT_LISTEN_US            750000u
#define OMCU_BOOT_SESSION_TIMEOUT_US   10000000u

#define OMCU_BOOT_CMD_HELLO            0x01u
#define OMCU_BOOT_CMD_BEGIN            0x02u
#define OMCU_BOOT_CMD_DATA             0x03u
#define OMCU_BOOT_CMD_END              0x04u
#define OMCU_BOOT_CMD_BOOT              0x05u

#define OMCU_BOOT_RESP_HELLO           0x81u
#define OMCU_BOOT_RESP_ACK             0x82u
#define OMCU_BOOT_RESP_NACK            0x83u

enum omcu_boot_error {
  OMCU_BOOT_ERROR_BAD_FRAME = 1,
  OMCU_BOOT_ERROR_BAD_COMMAND = 2,
  OMCU_BOOT_ERROR_BAD_HEADER = 3,
  OMCU_BOOT_ERROR_NO_SESSION = 4,
  OMCU_BOOT_ERROR_BAD_OFFSET = 5,
  OMCU_BOOT_ERROR_BAD_DATA = 6,
  OMCU_BOOT_ERROR_FLASH_VERIFY = 7,
  OMCU_BOOT_ERROR_INCOMPLETE_IMAGE = 8,
  OMCU_BOOT_ERROR_IMAGE_VERIFY = 9,
};

enum omcu_boot_frame_result {
  OMCU_BOOT_FRAME_TIMEOUT = 0,
  OMCU_BOOT_FRAME_VALID = 1,
  OMCU_BOOT_FRAME_INVALID = 2,
};

typedef struct {
  uint8_t type;
  uint16_t sequence;
  uint16_t length;
  uint8_t payload[OMCU_BOOT_FRAME_MAX_PAYLOAD];
} omcu_boot_frame_t;

typedef struct {
  omcu_image_header_t header;
  uint32_t slot_offset;
} omcu_boot_image_t;

typedef struct {
  bool active;
  omcu_image_header_t header;
  uint32_t slot_offset;
  uint32_t next_payload_offset;
} omcu_boot_session_t;

static uint32_t omcu_boot_crc32_byte(uint32_t crc, uint8_t byte) {
  uint32_t bit;

  crc ^= (uint32_t)byte;
  for (bit = 0u; bit < 8u; ++bit) {
    crc = (crc >> 1u) ^ ((crc & 1u) != 0u ? UINT32_C(0xEDB88320) : 0u);
  }
  return crc;
}

static uint32_t omcu_boot_crc32_word_le(uint32_t crc, uint32_t word) {
  crc = omcu_boot_crc32_byte(crc, (uint8_t)(word & 0xffu));
  crc = omcu_boot_crc32_byte(crc, (uint8_t)((word >> 8u) & 0xffu));
  crc = omcu_boot_crc32_byte(crc, (uint8_t)((word >> 16u) & 0xffu));
  return omcu_boot_crc32_byte(crc, (uint8_t)((word >> 24u) & 0xffu));
}

static uint32_t omcu_boot_read_le32(const uint8_t *bytes) {
  return (uint32_t)bytes[0] |
         ((uint32_t)bytes[1] << 8u) |
         ((uint32_t)bytes[2] << 16u) |
         ((uint32_t)bytes[3] << 24u);
}

static void omcu_boot_write_le32(uint8_t *bytes, uint32_t value) {
  bytes[0] = (uint8_t)(value & 0xffu);
  bytes[1] = (uint8_t)((value >> 8u) & 0xffu);
  bytes[2] = (uint8_t)((value >> 16u) & 0xffu);
  bytes[3] = (uint8_t)((value >> 24u) & 0xffu);
}

static void omcu_boot_timer_start(void) {
  OMCU_TIMER0->ctrl = 0u;
  OMCU_TIMER0->prescale = 26u;  /* 27 MHz / 27 = 1 MHz. */
  OMCU_TIMER0->count = 0u;
  OMCU_TIMER0->compare = UINT32_MAX;
  OMCU_TIMER0->status = OMCU_TIMER_STATUS_PENDING;
  OMCU_TIMER0->ctrl = OMCU_TIMER_CTRL_ENABLE;
}

static uint32_t omcu_boot_time_us(void) {
  return OMCU_TIMER0->count;
}

static bool omcu_boot_timeout_elapsed(uint32_t start_us, uint32_t timeout_us) {
  return (uint32_t)(omcu_boot_time_us() - start_us) >= timeout_us;
}

static void omcu_boot_uart_init(void) {
  /* 27 MHz / 115200 baud rounds to 234 clocks per bit; UART expects -1.
   * Keep this literal so the standalone ROM has no compiler division helper
   * dependency during the earliest boot stage. */
  omcu_uart0_init(233u, false);
}

static void omcu_boot_uart_put(uint8_t byte) {
  omcu_uart0_write_byte(byte);
}

static void omcu_boot_uart_wait_tx_idle(void) {
  while (!omcu_uart0_tx_ready()) {
  }
}

static bool omcu_boot_uart_get_until(uint8_t *byte, uint32_t start_us,
                                     uint32_t timeout_us) {
  while (!omcu_boot_timeout_elapsed(start_us, timeout_us)) {
    if (omcu_uart0_rx_ready()) {
      *byte = omcu_uart0_read_byte();
      return true;
    }
  }
  return false;
}

static uint32_t omcu_boot_frame_crc_begin(const omcu_boot_frame_t *frame) {
  uint32_t crc = UINT32_C(0xFFFFFFFF);

  crc = omcu_boot_crc32_byte(crc, frame->type);
  crc = omcu_boot_crc32_byte(crc, (uint8_t)(frame->sequence & 0xffu));
  crc = omcu_boot_crc32_byte(crc, (uint8_t)(frame->sequence >> 8u));
  crc = omcu_boot_crc32_byte(crc, (uint8_t)(frame->length & 0xffu));
  return omcu_boot_crc32_byte(crc, (uint8_t)(frame->length >> 8u));
}

static uint32_t omcu_boot_frame_crc(const omcu_boot_frame_t *frame) {
  uint32_t crc = omcu_boot_frame_crc_begin(frame);
  uint16_t index;

  for (index = 0u; index < frame->length; ++index) {
    crc = omcu_boot_crc32_byte(crc, frame->payload[index]);
  }
  return ~crc;
}

static void omcu_boot_send_frame(uint8_t type, uint16_t sequence,
                                 const uint8_t *payload, uint16_t length) {
  omcu_boot_frame_t frame;
  uint16_t index;
  uint32_t crc;

  frame.type = type;
  frame.sequence = sequence;
  frame.length = length;
  for (index = 0u; index < length; ++index) {
    frame.payload[index] = payload[index];
  }
  crc = omcu_boot_frame_crc(&frame);

  omcu_boot_uart_put(OMCU_BOOT_SOF0);
  omcu_boot_uart_put(OMCU_BOOT_SOF1);
  omcu_boot_uart_put(type);
  omcu_boot_uart_put((uint8_t)(sequence & 0xffu));
  omcu_boot_uart_put((uint8_t)(sequence >> 8u));
  omcu_boot_uart_put((uint8_t)(length & 0xffu));
  omcu_boot_uart_put((uint8_t)(length >> 8u));
  for (index = 0u; index < length; ++index) {
    omcu_boot_uart_put(payload[index]);
  }
  omcu_boot_uart_put((uint8_t)(crc & 0xffu));
  omcu_boot_uart_put((uint8_t)((crc >> 8u) & 0xffu));
  omcu_boot_uart_put((uint8_t)((crc >> 16u) & 0xffu));
  omcu_boot_uart_put((uint8_t)((crc >> 24u) & 0xffu));
}

static void omcu_boot_send_ack(uint16_t sequence) {
  static const uint8_t response[] = { 0u };
  omcu_boot_send_frame(OMCU_BOOT_RESP_ACK, sequence, response,
                       (uint16_t)sizeof(response));
}

static void omcu_boot_send_nack(uint16_t sequence, enum omcu_boot_error error) {
  uint8_t response[1];
  response[0] = (uint8_t)error;
  omcu_boot_send_frame(OMCU_BOOT_RESP_NACK, sequence, response,
                       (uint16_t)sizeof(response));
}

static enum omcu_boot_frame_result omcu_boot_receive_frame(
  omcu_boot_frame_t *frame, uint32_t timeout_us
) {
  uint32_t start_us = omcu_boot_time_us();
  uint8_t byte;
  uint8_t previous = 0u;
  uint8_t crc_bytes[4];
  uint32_t received_crc;
  uint16_t index;

  for (;;) {
    if (!omcu_boot_uart_get_until(&byte, start_us, timeout_us)) {
      return OMCU_BOOT_FRAME_TIMEOUT;
    }
    if (previous == OMCU_BOOT_SOF0 && byte == OMCU_BOOT_SOF1) {
      break;
    }
    previous = byte;
  }

  if (!omcu_boot_uart_get_until(&frame->type, start_us, timeout_us) ||
      !omcu_boot_uart_get_until(&byte, start_us, timeout_us)) {
    return OMCU_BOOT_FRAME_TIMEOUT;
  }
  frame->sequence = byte;
  if (!omcu_boot_uart_get_until(&byte, start_us, timeout_us)) {
    return OMCU_BOOT_FRAME_TIMEOUT;
  }
  frame->sequence |= (uint16_t)byte << 8u;
  if (!omcu_boot_uart_get_until(&byte, start_us, timeout_us)) {
    return OMCU_BOOT_FRAME_TIMEOUT;
  }
  frame->length = byte;
  if (!omcu_boot_uart_get_until(&byte, start_us, timeout_us)) {
    return OMCU_BOOT_FRAME_TIMEOUT;
  }
  frame->length |= (uint16_t)byte << 8u;
  if (frame->length > OMCU_BOOT_FRAME_MAX_PAYLOAD) {
    return OMCU_BOOT_FRAME_INVALID;
  }

  for (index = 0u; index < frame->length; ++index) {
    if (!omcu_boot_uart_get_until(&frame->payload[index], start_us, timeout_us)) {
      return OMCU_BOOT_FRAME_TIMEOUT;
    }
  }
  for (index = 0u; index < 4u; ++index) {
    if (!omcu_boot_uart_get_until(&crc_bytes[index], start_us, timeout_us)) {
      return OMCU_BOOT_FRAME_TIMEOUT;
    }
  }
  received_crc = omcu_boot_read_le32(crc_bytes);
  return received_crc == omcu_boot_frame_crc(frame) ? OMCU_BOOT_FRAME_VALID
                                                     : OMCU_BOOT_FRAME_INVALID;
}

static volatile uint32_t *omcu_boot_flash_word(uint32_t offset) {
  return (volatile uint32_t *)(uintptr_t)(OMCU_USER_FLASH_BASE + offset);
}

static uint32_t omcu_boot_flash_read_word(uint32_t offset) {
  return *omcu_boot_flash_word(offset);
}

static void omcu_boot_flash_program_word(uint32_t offset, uint32_t value) {
  *omcu_boot_flash_word(offset) = value;
}

static void omcu_boot_flash_erase_page(uint32_t offset) {
  volatile uint8_t *page =
    (volatile uint8_t *)(uintptr_t)(OMCU_USER_FLASH_BASE + offset);
  *page = 0u;
}

static void omcu_boot_flash_read_header(uint32_t slot_offset,
                                        omcu_image_header_t *header) {
  uint32_t *words = (uint32_t *)(void *)header;
  uint32_t index;

  for (index = 0u; index < OMCU_IMAGE_HEADER_BYTES / 4u; ++index) {
    words[index] = omcu_boot_flash_read_word(slot_offset + index * 4u);
  }
}

static bool omcu_boot_flash_header_matches(uint32_t slot_offset,
                                           const omcu_image_header_t *header) {
  const uint32_t *words = (const uint32_t *)(const void *)header;
  uint32_t index;

  for (index = 0u; index < OMCU_IMAGE_HEADER_BYTES / 4u; ++index) {
    if (omcu_boot_flash_read_word(slot_offset + index * 4u) != words[index]) {
      return false;
    }
  }
  return true;
}

static void omcu_boot_flash_write_header(uint32_t slot_offset,
                                         const omcu_image_header_t *header) {
  const uint32_t *words = (const uint32_t *)(const void *)header;
  uint32_t index;

  for (index = 0u; index < OMCU_IMAGE_HEADER_BYTES / 4u; ++index) {
    omcu_boot_flash_program_word(slot_offset + index * 4u, words[index]);
  }
}

static uint32_t omcu_boot_header_crc32(const omcu_image_header_t *header) {
  const uint32_t *words = (const uint32_t *)(const void *)header;
  uint32_t crc = UINT32_C(0xFFFFFFFF);
  uint32_t index;

  for (index = 0u; index < OMCU_IMAGE_HEADER_BYTES / 4u; ++index) {
    uint32_t word = words[index];
    if (index == OMCU_IMAGE_HEADER_STATE_OFFSET / 4u ||
        index == OMCU_IMAGE_HEADER_CRC_OFFSET / 4u) {
      word = 0u;
    }
    crc = omcu_boot_crc32_word_le(crc, word);
  }
  return ~crc;
}

static bool omcu_boot_header_is_valid(const omcu_image_header_t *header,
                                      uint32_t expected_state) {
  uint32_t index;

  if (header->magic != OMCU_IMAGE_MAGIC ||
      header->format_version != OMCU_IMAGE_FORMAT_VERSION ||
      header->header_bytes != OMCU_IMAGE_HEADER_BYTES ||
      header->hardware_abi != OMCU_IMAGE_HARDWARE_ABI ||
      header->load_address != OMCU_APPLICATION_LOAD_ADDRESS ||
      header->entry_address != OMCU_APPLICATION_LOAD_ADDRESS ||
      header->payload_bytes == 0u ||
      header->payload_bytes > OMCU_IMAGE_PAYLOAD_MAX_BYTES ||
      (header->payload_bytes & 3u) != 0u || header->state != expected_state ||
      header->header_crc32 != omcu_boot_header_crc32(header)) {
    return false;
  }
  for (index = 0u; index < 6u; ++index) {
    if (header->reserved[index] != 0u) {
      return false;
    }
  }
  return true;
}

static uint32_t omcu_boot_payload_crc32(uint32_t slot_offset,
                                        uint32_t payload_bytes) {
  uint32_t crc = UINT32_C(0xFFFFFFFF);
  uint32_t offset;

  for (offset = 0u; offset < payload_bytes; offset += 4u) {
    crc = omcu_boot_crc32_word_le(
      crc,
      omcu_boot_flash_read_word(slot_offset + OMCU_IMAGE_HEADER_BYTES + offset)
    );
  }
  return ~crc;
}

static bool omcu_boot_sequence_is_newer(uint32_t candidate, uint32_t current) {
  return (int32_t)(candidate - current) > 0;
}

static bool omcu_boot_find_valid_image(omcu_boot_image_t *selected) {
  bool found = false;
  uint32_t slot_index;

  for (slot_index = 0u; slot_index < OMCU_IMAGE_SLOT_COUNT; ++slot_index) {
    omcu_boot_image_t candidate;

    candidate.slot_offset = slot_index * OMCU_IMAGE_SLOT_BYTES;
    omcu_boot_flash_read_header(candidate.slot_offset, &candidate.header);
    if (!omcu_boot_header_is_valid(&candidate.header, OMCU_IMAGE_STATE_COMMITTED) ||
        omcu_boot_payload_crc32(candidate.slot_offset,
                                candidate.header.payload_bytes) !=
          candidate.header.payload_crc32) {
      continue;
    }
    if (!found || omcu_boot_sequence_is_newer(candidate.header.sequence,
                                              selected->header.sequence)) {
      *selected = candidate;
      found = true;
    }
  }
  return found;
}

static void omcu_boot_send_hello(uint16_t sequence) {
  omcu_boot_image_t selected;
  uint8_t response[16];
  bool valid = omcu_boot_find_valid_image(&selected);

  response[0] = OMCU_BOOT_PROTOCOL_VERSION;
  response[1] = valid ? 1u : 0u;
  response[2] = valid ? (uint8_t)(selected.slot_offset / OMCU_IMAGE_SLOT_BYTES)
                      : 0xffu;
  response[3] = 0u;
  omcu_boot_write_le32(&response[4],
                        valid ? selected.header.sequence : 0u);
  omcu_boot_write_le32(&response[8],
                        valid ? selected.header.payload_bytes : 0u);
  omcu_boot_write_le32(&response[12], OMCU_IMAGE_HARDWARE_ABI);
  omcu_boot_send_frame(OMCU_BOOT_RESP_HELLO, sequence, response,
                       (uint16_t)sizeof(response));
}

static bool omcu_boot_begin_update(const omcu_boot_frame_t *frame,
                                   omcu_boot_session_t *session) {
  omcu_boot_image_t selected;
  uint8_t *header_bytes = (uint8_t *)(void *)&session->header;
  uint32_t page_index;
  uint32_t index;
  bool has_current;

  if (frame->length != OMCU_IMAGE_HEADER_BYTES) {
    return false;
  }
  for (index = 0u; index < OMCU_IMAGE_HEADER_BYTES; ++index) {
    header_bytes[index] = frame->payload[index];
  }
  if (!omcu_boot_header_is_valid(&session->header, OMCU_IMAGE_STATE_STAGING)) {
    return false;
  }

  has_current = omcu_boot_find_valid_image(&selected);
  session->slot_offset = has_current
    ? (selected.slot_offset ^ OMCU_IMAGE_SLOT_BYTES)
    : OMCU_IMAGE_SLOT_A_OFFSET;
  session->header.sequence = has_current ? selected.header.sequence + 1u : 1u;
  session->header.state = OMCU_IMAGE_STATE_STAGING;
  session->header.header_crc32 = 0u;
  session->header.header_crc32 = omcu_boot_header_crc32(&session->header);

  for (page_index = 0u; page_index < OMCU_IMAGE_SLOT_PAGES; ++page_index) {
    omcu_boot_flash_erase_page(
      session->slot_offset + page_index * OMCU_USER_FLASH_PAGE_BYTES
    );
  }
  omcu_boot_flash_write_header(session->slot_offset, &session->header);
  if (!omcu_boot_flash_header_matches(session->slot_offset, &session->header)) {
    return false;
  }

  session->next_payload_offset = 0u;
  session->active = true;
  return true;
}

static bool omcu_boot_write_data(const omcu_boot_frame_t *frame,
                                 omcu_boot_session_t *session) {
  uint32_t offset;
  uint16_t data_bytes;
  uint16_t index;

  if (!session->active || frame->length < 8u) {
    return false;
  }
  offset = omcu_boot_read_le32(frame->payload);
  data_bytes = (uint16_t)(frame->length - 4u);
  if (data_bytes == 0u || (data_bytes & 3u) != 0u ||
      offset > session->header.payload_bytes ||
      data_bytes > session->header.payload_bytes - offset) {
    return false;
  }

  /* A lost UART ACK makes the host retry the identical DATA packet. Verify
   * rather than reject that replay so stop-and-wait remains power/noise safe. */
  if (offset < session->next_payload_offset) {
    if (offset + data_bytes > session->next_payload_offset) {
      return false;
    }
    for (index = 0u; index < data_bytes; index += 4u) {
      uint32_t word = omcu_boot_read_le32(&frame->payload[4u + index]);
      uint32_t flash_offset = session->slot_offset + OMCU_IMAGE_HEADER_BYTES +
                              offset + index;
      if (omcu_boot_flash_read_word(flash_offset) != word) {
        return false;
      }
    }
    return true;
  }
  if (offset != session->next_payload_offset) {
    return false;
  }

  for (index = 0u; index < data_bytes; index += 4u) {
    uint32_t word = omcu_boot_read_le32(&frame->payload[4u + index]);
    uint32_t flash_offset = session->slot_offset + OMCU_IMAGE_HEADER_BYTES +
                            offset + index;
    omcu_boot_flash_program_word(flash_offset, word);
    if (omcu_boot_flash_read_word(flash_offset) != word) {
      return false;
    }
  }
  session->next_payload_offset += data_bytes;
  return true;
}

static bool omcu_boot_finish_update(omcu_boot_session_t *session) {
  omcu_boot_image_t verified;

  if (!session->active ||
      session->next_payload_offset != session->header.payload_bytes ||
      omcu_boot_payload_crc32(session->slot_offset,
                              session->header.payload_bytes) !=
        session->header.payload_crc32) {
    return false;
  }

  /* This is the only irreversible commit point. A power loss before it leaves
   * the old slot bootable; a power loss after it leaves a fully CRC-verified
   * slot bootable. */
  omcu_boot_flash_program_word(session->slot_offset + OMCU_IMAGE_HEADER_STATE_OFFSET,
                               OMCU_IMAGE_STATE_COMMITTED);
  if (omcu_boot_flash_read_word(session->slot_offset +
                                OMCU_IMAGE_HEADER_STATE_OFFSET) !=
      OMCU_IMAGE_STATE_COMMITTED) {
    return false;
  }
  session->active = false;
  return omcu_boot_find_valid_image(&verified) &&
         verified.slot_offset == session->slot_offset;
}

static bool omcu_boot_session_is_committed(const omcu_boot_session_t *session) {
  omcu_boot_image_t verified;

  return omcu_boot_find_valid_image(&verified) &&
         verified.slot_offset == session->slot_offset &&
         verified.header.sequence == session->header.sequence &&
         verified.header.payload_crc32 == session->header.payload_crc32 &&
         verified.header.payload_bytes == session->header.payload_bytes;
}

static void omcu_boot_start_application(const omcu_boot_image_t *image) {
  volatile uint32_t *destination =
    (volatile uint32_t *)(uintptr_t)image->header.load_address;
  uint32_t offset;
  void (*entry)(void) = (void (*)(void))(uintptr_t)image->header.entry_address;

  for (offset = 0u; offset < image->header.payload_bytes; offset += 4u) {
    destination[offset / 4u] = omcu_boot_flash_read_word(
      image->slot_offset + OMCU_IMAGE_HEADER_BYTES + offset
    );
  }
  entry();
  for (;;) {
  }
}

static bool omcu_boot_handle_frame(const omcu_boot_frame_t *frame,
                                   omcu_boot_session_t *session) {
  switch (frame->type) {
    case OMCU_BOOT_CMD_HELLO:
      if (frame->length != 0u) {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_BAD_COMMAND);
      } else {
        omcu_boot_send_hello(frame->sequence);
      }
      return false;

    case OMCU_BOOT_CMD_BEGIN:
      if (omcu_boot_begin_update(frame, session)) {
        omcu_boot_send_ack(frame->sequence);
      } else {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_BAD_HEADER);
      }
      return false;

    case OMCU_BOOT_CMD_DATA:
      if (!session->active) {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_NO_SESSION);
      } else if (omcu_boot_write_data(frame, session)) {
        omcu_boot_send_ack(frame->sequence);
      } else {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_BAD_DATA);
      }
      return false;

    case OMCU_BOOT_CMD_END:
      if (frame->length != 0u) {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_BAD_COMMAND);
      } else if (!session->active && omcu_boot_session_is_committed(session)) {
        /* END is idempotent if the original commit ACK was lost. */
        omcu_boot_send_ack(frame->sequence);
      } else if (!session->active) {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_NO_SESSION);
      } else if (session->next_payload_offset != session->header.payload_bytes) {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_INCOMPLETE_IMAGE);
      } else if (omcu_boot_finish_update(session)) {
        omcu_boot_send_ack(frame->sequence);
      } else {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_IMAGE_VERIFY);
      }
      return false;

    case OMCU_BOOT_CMD_BOOT:
      if (frame->length != 0u) {
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_BAD_COMMAND);
      } else {
        omcu_boot_image_t selected;
        if (omcu_boot_find_valid_image(&selected)) {
          omcu_boot_send_ack(frame->sequence);
          return true;
        }
        omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_IMAGE_VERIFY);
      }
      return false;

    default:
      omcu_boot_send_nack(frame->sequence, OMCU_BOOT_ERROR_BAD_COMMAND);
      return false;
  }
}

void omcu_bootloader_main(void) {
  omcu_boot_image_t selected;
  static omcu_boot_session_t session;
  omcu_boot_frame_t frame;
  bool has_image;
  bool saw_valid_frame = false;

  omcu_boot_timer_start();
  omcu_boot_uart_init();
  has_image = omcu_boot_find_valid_image(&selected);

  for (;;) {
    enum omcu_boot_frame_result result = omcu_boot_receive_frame(
      &frame,
      (has_image && !saw_valid_frame && !session.active)
        ? OMCU_BOOT_LISTEN_US
        : OMCU_BOOT_SESSION_TIMEOUT_US
    );

    if (result == OMCU_BOOT_FRAME_TIMEOUT) {
      if (has_image && !session.active) {
        omcu_boot_start_application(&selected);
      }
      if (session.active) {
        session.active = false;
      }
      continue;
    }
    if (result == OMCU_BOOT_FRAME_INVALID) {
      /* No sequence can be trusted from a corrupted frame. Keep listening. */
      continue;
    }

    saw_valid_frame = true;
    if (omcu_boot_handle_frame(&frame, &session)) {
      omcu_boot_uart_wait_tx_idle();
      if (omcu_boot_find_valid_image(&selected)) {
        omcu_boot_start_application(&selected);
      }
    }
    has_image = omcu_boot_find_valid_image(&selected);
  }
}
