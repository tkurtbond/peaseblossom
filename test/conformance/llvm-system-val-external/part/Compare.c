/* Compare.Mod's part in C: a comparison for qsort */
#include <stdint.h>

int CompareIntegers(const void *a, const void *b) __asm__("Compare.-integers");
int CompareIntegers(const void *a, const void *b)
{
  int32_t x = *(const int32_t *) a, y = *(const int32_t *) b;
  return x < y ? -1 : x > y;
}
