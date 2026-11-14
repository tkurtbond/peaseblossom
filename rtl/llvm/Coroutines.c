/* Coroutines.c - the part of Coroutines.Mod written in C
   (doc/developer/coroutines.md, decision 6): the context switch and a
   new coroutine's first frame for each architecture, the stacks, and the
   messages of traps 16-18.

   The switch saves the callee-saved registers and the floating-point
   control registers on the stack it leaves, stores that stack pointer
   through its first argument, loads the second, restores the same
   registers from there and returns into the coroutine it resumes. A new
   coroutine's stack holds a frame laid out as the switch leaves one, whose
   return address is the trampoline, which calls the body. On x86-64 the
   floating-point state is MXCSR and the x87 control word, on i386 the x87
   control word alone (a Pentium II has no MXCSR), on arm64 FPCR.

   The trampoline's call-frame information marks its return address
   undefined, so that a debugger's backtrace ends there
   (doc/research/concurrency-survey.md, 8.7.2).

   The names contain "-", as Platform.c's do. */

#include <stddef.h>
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>
#include <sys/mman.h>

#define NAME(n) __asm__("Coroutines.-" n)

/* Platform.c's count of signal handlers running (decision 7). */
extern volatile int32_t PlatformHandlersRunning __asm__("Platform.-handlers-running");

static void trap(const char *message, int status)
{
  write(2, message, strlen(message));
  exit(status);
}

/* Called by the trampoline when a body returns (trap 16), and with a NIL
   body (trap 4, as a call of a NIL procedure value is). Static, so that
   the trampoline's calls need no PLT in the shared library, and with
   C's own names: -lto lists such a function in a .lto_discard directive,
   where clang 19 and 21 reject a name with a "-" in it. */
static void coroutines_body_returned(void) __attribute__((used));
static void coroutines_body_returned(void) { trap("coroutine body returned\n", 16); }
static void coroutines_nil_body(void) __attribute__((used));
static void coroutines_nil_body(void) { trap("NIL pointer dereference\n", 4); }

/* Trap 17, misuse: which is Coroutines.Mod's number of the case. */
void CoroutinesMisuse(int32_t which) NAME("misuse");
void CoroutinesMisuse(int32_t which)
{
  static const char *const texts[] = {
    "Transfer to a coroutine never initialized\n",
    "Transfer to a freed coroutine\n",
    "Free of the running coroutine\n",
    "Free of the main program's coroutine\n",
    "Transfer in a finalizer\n",
    "Transfer in a signal handler\n",
  };
  if (which < 0 || which >= (int32_t)(sizeof texts / sizeof texts[0])) which = 0;
  trap(texts[which], 17);
}

/* Whether a signal handler is running (decision 7). */
int32_t CoroutinesInSignalHandler(void) NAME("in-signal-handler");
int32_t CoroutinesInSignalHandler(void) { return PlatformHandlersRunning > 0; }

#if defined(__x86_64__)
/* switch(from, to): from is where to store this stack's pointer, to the
   pointer of the stack to resume. The frame it leaves, from the stored
   pointer up: MXCSR (4 bytes), the x87 control word (2, padded to 8),
   r15, r14, r13, r12, rbx, rbp, the return address. */
__asm__(
  "  .text\n"
  "  .globl \"Coroutines.-switch\"\n"
  "  .type \"Coroutines.-switch\",@function\n"
  "\"Coroutines.-switch\":\n"
  "  pushq %rbp\n  pushq %rbx\n  pushq %r12\n  pushq %r13\n  pushq %r14\n  pushq %r15\n"
  "  subq $8, %rsp\n  stmxcsr (%rsp)\n  fnstcw 4(%rsp)\n"
  "  movq %rsp, (%rdi)\n  movq %rsi, %rsp\n"
  "  ldmxcsr (%rsp)\n  fldcw 4(%rsp)\n  addq $8, %rsp\n"
  "  popq %r15\n  popq %r14\n  popq %r13\n  popq %r12\n  popq %rbx\n  popq %rbp\n"
  "  ret\n"
  "  .size \"Coroutines.-switch\", .-\"Coroutines.-switch\"\n"
  /* entered by the switch's ret with the body in r12 and rsp 8 below a
     16-byte boundary */
  "  .type \"Coroutines.-start\",@function\n"
  "\"Coroutines.-start\":\n"
  "  .cfi_startproc\n  .cfi_undefined rip\n"
  "  subq $8, %rsp\n  xorl %ebp, %ebp\n"
  "  testq %r12, %r12\n  jz 1f\n"
  "  callq *%r12\n"
  "  callq coroutines_body_returned\n"
  "1:  callq coroutines_nil_body\n  ud2\n"
  "  .cfi_endproc\n"
  "  .size \"Coroutines.-start\", .-\"Coroutines.-start\"\n");
#define FRAME_WORDS 9
static void first_frame(uintptr_t *top, uintptr_t body, uintptr_t start)
{
  /* top[-1] padding, top[-2] the return address, then rbp rbx r12 r13 r14
     r15, and the floating-point word: MXCSR's and the x87 control word's
     values at reset */
  top[-1] = 0; top[-2] = start;
  top[-3] = 0; top[-4] = 0; top[-5] = body; top[-6] = 0; top[-7] = 0; top[-8] = 0;
  top[-9] = 0x1F80 | ((uintptr_t)0x037F << 32);
}
#elif defined(__i386__)
/* switch(from, to), the arguments on the stack. The frame it leaves: the
   x87 control word (padded to 4 bytes), edi, esi, ebx, ebp, the return
   address. */
__asm__(
  "  .text\n"
  "  .globl \"Coroutines.-switch\"\n"
  "  .type \"Coroutines.-switch\",@function\n"
  "\"Coroutines.-switch\":\n"
  "  movl 4(%esp), %eax\n  movl 8(%esp), %edx\n"
  "  pushl %ebp\n  pushl %ebx\n  pushl %esi\n  pushl %edi\n"
  "  subl $4, %esp\n  fnstcw (%esp)\n"
  "  movl %esp, (%eax)\n  movl %edx, %esp\n"
  "  fldcw (%esp)\n  addl $4, %esp\n"
  "  popl %edi\n  popl %esi\n  popl %ebx\n  popl %ebp\n"
  "  ret\n"
  "  .size \"Coroutines.-switch\", .-\"Coroutines.-switch\"\n"
  /* entered by the switch's ret with the body in ebx and esp 4 below a
     16-byte boundary */
  "  .type \"Coroutines.-start\",@function\n"
  "\"Coroutines.-start\":\n"
  "  .cfi_startproc\n  .cfi_undefined eip\n"
  "  subl $12, %esp\n  xorl %ebp, %ebp\n"
  "  testl %ebx, %ebx\n  jz 1f\n"
  "  call *%ebx\n"
  "  call coroutines_body_returned\n"
  "1:  call coroutines_nil_body\n  ud2\n"
  "  .cfi_endproc\n"
  "  .size \"Coroutines.-start\", .-\"Coroutines.-start\"\n");
#define FRAME_WORDS 7
static void first_frame(uintptr_t *top, uintptr_t body, uintptr_t start)
{
  /* top[-1] padding, top[-2] the return address, ebp ebx esi edi, and the
     x87 control word at reset */
  top[-1] = 0; top[-2] = start; top[-3] = 0; top[-4] = body; top[-5] = 0; top[-6] = 0;
  top[-7] = 0x037F;
}
#elif defined(__aarch64__)
/* switch(from, to) in x0 and x1. The frame it leaves, 176 bytes: x19-x28,
   x29 and x30 (the return address), d8-d15, FPCR, padding. */
__asm__(
  "  .text\n"
  "  .globl \"Coroutines.-switch\"\n"
  "  .type \"Coroutines.-switch\",%function\n"
  "\"Coroutines.-switch\":\n"
  "  sub sp, sp, #176\n"
  "  stp x19, x20, [sp, #0]\n  stp x21, x22, [sp, #16]\n  stp x23, x24, [sp, #32]\n"
  "  stp x25, x26, [sp, #48]\n  stp x27, x28, [sp, #64]\n  stp x29, x30, [sp, #80]\n"
  "  stp d8, d9, [sp, #96]\n  stp d10, d11, [sp, #112]\n"
  "  stp d12, d13, [sp, #128]\n  stp d14, d15, [sp, #144]\n"
  "  mrs x2, fpcr\n  str x2, [sp, #160]\n"
  "  mov x2, sp\n  str x2, [x0]\n  mov sp, x1\n"
  "  ldr x2, [sp, #160]\n  msr fpcr, x2\n"
  "  ldp x19, x20, [sp, #0]\n  ldp x21, x22, [sp, #16]\n  ldp x23, x24, [sp, #32]\n"
  "  ldp x25, x26, [sp, #48]\n  ldp x27, x28, [sp, #64]\n  ldp x29, x30, [sp, #80]\n"
  "  ldp d8, d9, [sp, #96]\n  ldp d10, d11, [sp, #112]\n"
  "  ldp d12, d13, [sp, #128]\n  ldp d14, d15, [sp, #144]\n"
  "  add sp, sp, #176\n"
  "  ret\n"
  "  .size \"Coroutines.-switch\", .-\"Coroutines.-switch\"\n"
  /* entered by the switch's ret with the body in x19 and sp at the top */
  "  .type \"Coroutines.-start\",%function\n"
  "\"Coroutines.-start\":\n"
  "  .cfi_startproc\n  .cfi_undefined x30\n"
  "  mov x29, #0\n"
  "  cbz x19, 1f\n"
  "  blr x19\n"
  "  bl coroutines_body_returned\n"
  "1:  bl coroutines_nil_body\n  brk #0\n"
  "  .cfi_endproc\n"
  "  .size \"Coroutines.-start\", .-\"Coroutines.-start\"\n");
#define FRAME_WORDS 22
static void first_frame(uintptr_t *top, uintptr_t body, uintptr_t start)
{
  uintptr_t *frame = top - FRAME_WORDS;
  int i;
  for (i = 0; i < FRAME_WORDS; i++) frame[i] = 0;
  frame[0] = body;   /* x19 */
  frame[11] = start; /* x30 */
}
#else
#error "Coroutines.c: no context switch for this architecture"
#endif

extern char coroutines_start[] __asm__("Coroutines.-start") __attribute__((visibility("hidden")));

/* A stack of size bytes, rounded up to whole pages, above a guard page
   that is not counted, holding a first frame that calls body: its bounds
   in *low and *high, and the stack pointer for the switch to resume; 0
   when the system refuses the memory, or the size does not fit. */
uintptr_t CoroutinesNewStack(uintptr_t body, int64_t size, uintptr_t *low, uintptr_t *high) NAME("new-stack");
uintptr_t CoroutinesNewStack(uintptr_t body, int64_t size, uintptr_t *low, uintptr_t *high)
{
  size_t page = (size_t)sysconf(_SC_PAGESIZE), usable, total;
  int flags = MAP_PRIVATE | MAP_ANON;
  char *memory;
  uintptr_t *top;
  if (size < 0) size = 0;
  if ((uint64_t)size > (uint64_t)(SIZE_MAX / 2)) return 0;
  usable = ((size_t)size + page - 1) / page * page;
  total = usable + page;
#if defined(__OpenBSD__)
  /* OpenBSD requires a stack pointer to point into a MAP_STACK region;
     FreeBSD's MAP_STACK is a region that grows down, which is not wanted
     (decision 6) */
  flags |= MAP_STACK;
#endif
  memory = mmap(NULL, total, PROT_READ | PROT_WRITE, flags, -1, 0);
  if (memory == MAP_FAILED) return 0;
  if (mprotect(memory, page, PROT_NONE) != 0) { munmap(memory, total); return 0; }
  top = (uintptr_t *)(memory + total);
  first_frame(top, body, (uintptr_t)coroutines_start);
  *low = (uintptr_t)(memory + page);
  *high = (uintptr_t)top;
  return (uintptr_t)(top - FRAME_WORDS);
}

/* Gives back a stack CoroutinesNewStack made, its guard page with it. */
void CoroutinesFreeStack(uintptr_t low, uintptr_t high) NAME("free-stack");
void CoroutinesFreeStack(uintptr_t low, uintptr_t high)
{
  size_t page = (size_t)sysconf(_SC_PAGESIZE);
  munmap((char *)low - page, (size_t)(high - low) + page);
}

/* Trap 18: Init could not get the stack. */
void CoroutinesNoStack(void) NAME("no-stack");
void CoroutinesNoStack(void) { trap("no memory for a coroutine's stack\n", 18); }
