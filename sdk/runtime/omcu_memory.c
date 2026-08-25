#include <stddef.h>
#include <stdint.h>

/*
 * The freestanding bootloader must not depend on a host C library. GCC can
 * lower structure copies into memcpy even with -ffreestanding, so provide the
 * small, byte-exact implementation needed by the immutable ROM.
 */
void *memcpy(void *destination, const void *source, size_t count) {
  volatile uint8_t *out = (volatile uint8_t *)destination;
  const volatile uint8_t *in = (const volatile uint8_t *)source;
  void *result = destination;

  while (count != 0u) {
    *out = *in;
    ++out;
    ++in;
    --count;
  }
  return result;
}
