/* CoroutineBench's part in C: a clock, the process's sizes, and
   swapcontext for comparison with Coroutines.Transfer. */
#include <stdint.h>
#include <stdio.h>
#include <string.h>
#include <time.h>
#if defined(__linux__) || defined(__NetBSD__) || defined(__FreeBSD__)
#define HAVE_UCONTEXT 1
#include <ucontext.h>
#endif

int64_t bench_ns(void)
{
  struct timespec t;
  clock_gettime(CLOCK_MONOTONIC, &t);
  return (int64_t)t.tv_sec * 1000000000 + t.tv_nsec;
}

/* resident (virtual = 0) or virtual size in kB, from /proc (Linux), else -1 */
int64_t bench_kb(int32_t virtual)
{
  const char *key = virtual ? "VmSize:" : "VmRSS:";
  char line[256];
  long long kb = -1;
  FILE *f = fopen("/proc/self/status", "r");
  if (f == NULL) return -1;
  while (fgets(line, sizeof line, f) != NULL)
    if (strncmp(line, key, strlen(key)) == 0)
      sscanf(line + strlen(key), "%lld", &kb);
  fclose(f);
  return kb;
}

#ifdef HAVE_UCONTEXT
static ucontext_t main_context, other_context;
static char other_stack[65536];

static void other(void)
{
  for (;;) swapcontext(&other_context, &main_context);
}

/* the time of rounds round trips, or -1 where there is no swapcontext */
int64_t bench_swapcontext(long rounds)
{
  long n;
  int64_t t0;
  getcontext(&other_context);
  other_context.uc_stack.ss_sp = other_stack;
  other_context.uc_stack.ss_size = sizeof other_stack;
  other_context.uc_link = NULL;
  makecontext(&other_context, other, 0);
  t0 = bench_ns();
  for (n = 0; n < rounds; n++) swapcontext(&main_context, &other_context);
  return bench_ns() - t0;
}
#else
int64_t bench_swapcontext(long rounds)
{
  (void)rounds;
  return -1;
}
#endif
