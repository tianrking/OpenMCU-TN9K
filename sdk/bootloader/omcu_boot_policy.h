#ifndef OMCU_BOOT_POLICY_H_
#define OMCU_BOOT_POLICY_H_

#include "omcu_image.h"

#include <stdbool.h>
#include <stdint.h>

/* Internal, side-effect-free update policy shared by the ROM and host tests. */
static inline uint32_t omcu_boot_erase_pages_for_payload(
  uint32_t payload_bytes
) {
  return (OMCU_IMAGE_HEADER_BYTES + payload_bytes +
          OMCU_USER_FLASH_PAGE_BYTES - 1u) /
         OMCU_USER_FLASH_PAGE_BYTES;
}

#endif  /* OMCU_BOOT_POLICY_H_ */
