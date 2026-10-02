#include <stddef.h>
#include <stdint.h>
#include "fnv.h"

int32_t poc_fixture_fnv1a(const unsigned char *s, size_t n) {
  uint32_t h = FNV_OFFSET_BASIS;
  for (size_t i = 0; i < n; i++) { h ^= s[i]; h *= FNV_PRIME; }
  return (int32_t)h;
}
