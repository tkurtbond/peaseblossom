/* Directories.c - the part of Directories.Mod written in C (PLAN.md
   Phase 16 step 4), compiled by clang for the target from the system's
   own headers, as Platform.c is: S_ISDIR is a macro of them, and mkdir's
   mode_t is 16 bits on FreeBSD, 32 elsewhere. The names contain "-", as
   Platform.c's do. */

#include <errno.h>
#include <stdint.h>
#include <sys/stat.h>
#include <sys/types.h>

#define NAME(n) __asm__("Directories.-" n)

/* Whether name is a directory. */
int32_t DirectoriesIsDirectory(const char *name) NAME("is-directory");
int32_t DirectoriesIsDirectory(const char *name)
{
  struct stat s;
  return stat(name, &s) == 0 && S_ISDIR(s.st_mode);
}

/* Makes the directory name, readable, writable and searchable by all but
   what the umask takes away: 0 or the errno value. */
int32_t DirectoriesMake(const char *name) NAME("make");
int32_t DirectoriesMake(const char *name)
{
  return mkdir(name, 0777) < 0 ? errno : 0;
}
