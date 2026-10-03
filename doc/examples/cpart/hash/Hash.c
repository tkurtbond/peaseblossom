#include <stddef.h>
#include <stdint.h>

int32_t hash_fnv1a(const unsigned char *s, size_t n) {
  uint32_t h = 2166136261u;
  for (size_t i = 0; i < n; i++) { h ^= s[i]; h *= 16777619u; }
  return (int32_t)h;
}
