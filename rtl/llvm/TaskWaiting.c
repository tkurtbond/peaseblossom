/* TaskWaiting.c - the part of TaskWaiting.Mod written in C
   (doc/developer/tasks.md, decision 1): the messages of traps 19 and 20.

   The names contain "-", as Platform.c's do. */

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <unistd.h>

#define NAME(n) __asm__("TaskWaiting.-" n)

static void trap(const char *message, int status)
{
  write(2, message, strlen(message));
  exit(status);
}

/* Trap 19: no task is ready and nothing can make one ready. */
void TaskWaitingDeadlock(void) NAME("deadlock");
void TaskWaitingDeadlock(void) { trap("all tasks are blocked\n", 19); }

/* Trap 20, misuse: which is TaskWaiting.Mod's number of the case. */
void TaskWaitingMisuse(int32_t which) NAME("misuse");
void TaskWaitingMisuse(int32_t which)
{
  static const char *const texts[] = {
    "Unlock of a mutex the running task does not hold\n",
    "Join of the running task\n",
    "Send on a closed channel\n",
    "Close of a channel already closed\n",
    "Start of a task already started\n",
    "NewChannel with a negative capacity\n",
  };
  if (which < 0 || which >= (int32_t)(sizeof texts / sizeof texts[0])) which = 0;
  trap(texts[which], 20);
}
