#ifndef OMCU_IMAGE_H_
#define OMCU_IMAGE_H_

/*
 * OpenMCU independent-application image contract.
 *
 * The immutable FPGA bitstream contains only the bootloader. Customer
 * applications are packed in this format, stored in the GW1NR-9C User Flash,
 * copied to SRAM after validation, and then entered at load_address. This
 * header intentionally contains no vendor-specific programming API.
 */

#include "omcu_regs.h"

#include <stdint.h>

#define OMCU_IMAGE_MAGIC                 UINT32_C(0x4F4D4355)
#define OMCU_IMAGE_FORMAT_VERSION        1u
#define OMCU_IMAGE_HEADER_BYTES          64u
#define OMCU_IMAGE_HEADER_STATE_OFFSET   32u
#define OMCU_IMAGE_HEADER_CRC_OFFSET     36u

#define OMCU_IMAGE_STATE_ERASED          UINT32_C(0xFFFFFFFF)
#define OMCU_IMAGE_STATE_STAGING         UINT32_C(0xFFFFFFFE)
#define OMCU_IMAGE_STATE_COMMITTED       UINT32_C(0xFFFFFFFC)

/* GW1NR-9C User Flash geometry exposed by the Tang Nano 9K product target. */
#define OMCU_USER_FLASH_BYTES            77824u
#define OMCU_USER_FLASH_PAGE_BYTES       2048u
#define OMCU_USER_FLASH_PAGE_COUNT       38u

/* Two 18-page application slots leave the final two pages reserved. */
#define OMCU_IMAGE_SLOT_COUNT            2u
#define OMCU_IMAGE_SLOT_PAGES            18u
#define OMCU_IMAGE_SLOT_BYTES            \
  (OMCU_IMAGE_SLOT_PAGES * OMCU_USER_FLASH_PAGE_BYTES)
#define OMCU_IMAGE_SLOT_A_OFFSET         0u
#define OMCU_IMAGE_SLOT_B_OFFSET         OMCU_IMAGE_SLOT_BYTES
#define OMCU_IMAGE_PAYLOAD_MAX_BYTES     \
  (OMCU_IMAGE_SLOT_BYTES - OMCU_IMAGE_HEADER_BYTES)

/* Application SRAM and bootloader scratch are intentionally disjoint. */
#define OMCU_APPLICATION_LOAD_ADDRESS    UINT32_C(0x10000000)
#define OMCU_APPLICATION_RAM_BYTES       (40u * 1024u)
#define OMCU_BOOTLOADER_RAM_BASE         \
  (OMCU_APPLICATION_LOAD_ADDRESS + OMCU_APPLICATION_RAM_BYTES)
#define OMCU_BOOTLOADER_RAM_BYTES        (4u * 1024u)

#define OMCU_IMAGE_HARDWARE_ABI          \
  (((uint32_t)OMCU_HW_ABI_MAJOR << 16u) | (uint32_t)OMCU_HW_ABI_MINOR)

typedef struct __attribute__((packed, aligned(4))) {
  uint32_t magic;
  uint16_t format_version;
  uint16_t header_bytes;
  uint32_t hardware_abi;
  uint32_t load_address;
  uint32_t entry_address;
  uint32_t payload_bytes;
  uint32_t payload_crc32;
  uint32_t sequence;
  uint32_t state;
  uint32_t header_crc32;
  uint32_t reserved[6];
} omcu_image_header_t;

_Static_assert(sizeof(omcu_image_header_t) == OMCU_IMAGE_HEADER_BYTES,
               "OpenMCU image header must be exactly 64 bytes");

#endif  /* OMCU_IMAGE_H_ */
