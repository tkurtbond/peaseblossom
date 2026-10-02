/* Twice.Mod's part in C */
#include <stdint.h>

int32_t TwiceDouble(int32_t x) __asm__("Twice.-double");
int32_t TwiceDouble(int32_t x) { return 2 * x; }
