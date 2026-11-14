/* Callback.Mod's part in C. */
#include <fenv.h>
#include <stdint.h>

#define NAME(n) __asm__("Callback.-" n)

void CallbackHold(uintptr_t (*make)(void), void (*pause)(void), void (*check)(uintptr_t)) NAME("hold");
void CallbackHold(uintptr_t (*make)(void), void (*pause)(void), void (*check)(uintptr_t))
{
  /* volatile: in this frame's memory, not in a register the switch saves */
  volatile uintptr_t held = make();
  pause();
  check(held);
}

void CallbackRoundUp(void) NAME("round-up");
void CallbackRoundUp(void) { fesetround(FE_UPWARD); }

int32_t CallbackRoundingUp(void) NAME("rounding-up");
int32_t CallbackRoundingUp(void) { return fegetround() == FE_UPWARD; }
