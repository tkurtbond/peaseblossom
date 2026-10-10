/* Platform.c - the part of Platform.Mod written in C (PLAN.md Phase 12
   step 5a, decided with the user 2026-10-02).

   Every call here differs between Linux, NetBSD, OpenBSD and FreeBSD in
   a way an Oberon declaration cannot follow, because poc does not know
   which of them it compiles for: the values of O_CREAT and O_TRUNC and of
   the errno codes, the function errno is reached through, the layout of
   struct stat, struct timeval and struct tm, and on NetBSD the names of
   the functions themselves (its headers rename stat, fstat,
   gettimeofday, nanosleep, localtime, mktime and utime to versioned
   symbols such as __stat50). The system's own headers know all of that,
   so these wrappers are compiled by clang for the target, beside
   Platform.Mod (the driver compiles a module's sibling .c whenever it
   compiles the module; LLVMToolchainDriver.CompanionSource).

   The interface is in fixed-width types only, so that it means the same
   under both of poc's size models: int32_t for a C int (a file
   descriptor, an errno value, a flag) and int64_t for everything else.
   A procedure that can fail returns 0 or the errno value, as voc's
   Platform does.

   The names contain "-", as the backend's own names do, so that no
   module's procedure or variable can be called the same. */

#define _FILE_OFFSET_BITS 64 /* a 64-bit off_t on 32-bit Linux too */

#include <errno.h>
#include <fcntl.h>
#include <limits.h>
#include <signal.h>
#include <stdint.h>
#include <string.h>
#include <sys/stat.h>
#include <sys/time.h>
#include <sys/types.h>
#include <time.h>
#include <unistd.h>
#include <utime.h>

#define NAME(n) __asm__("Platform.-" n)

/* The errno value left by the last call that failed. */
int32_t PlatformErrno(void) NAME("errno");
int32_t PlatformErrno(void) { return errno; }

/* ENOENT: Platform.Mod's error code for a name with no 0X in its array. */
int32_t PlatformNoSuchFile(void) NAME("no-such-file");
int32_t PlatformNoSuchFile(void) { return ENOENT; }

/* Whether e is one of the errno values of the class kind; the classes are
   Platform.Mod's error tests, in the order of its constants. */
int32_t PlatformIsError(int32_t kind, int32_t e) NAME("is-error");
int32_t PlatformIsError(int32_t kind, int32_t e)
{
  switch (kind) {
  case 0: return e == EMFILE || e == ENFILE;             /* TooManyFiles */
  case 1: return e == ENOENT;                            /* NoSuchDirectory, Absent */
  case 2: return e == EXDEV;                             /* DifferentFilesystems */
  case 3: return e == EACCES || e == EROFS || e == EAGAIN; /* Inaccessible */
  case 4: return e == ETIMEDOUT;                         /* TimedOut */
  case 5: return e == ECONNREFUSED || e == ECONNABORTED  /* ConnectionFailed */
              || e == ENETUNREACH || e == EHOSTUNREACH;
  case 6: return e == EINTR;                             /* Interrupted */
  default: return 0;
  }
}

int32_t PlatformMaxNameLength(void) NAME("max-name-length");
int32_t PlatformMaxNameLength(void) { return NAME_MAX; }

int32_t PlatformMaxPathLength(void) NAME("max-path-length");
int32_t PlatformMaxPathLength(void) { return PATH_MAX; }

/* Opens the file name: mode 0 to read, 1 to read and write, 2 created (or
   emptied) to read and write, with permissions 0664 less the umask, as
   voc's. */
int32_t PlatformOpen(const char *name, int32_t mode, int32_t *handle) NAME("open");
int32_t PlatformOpen(const char *name, int32_t mode, int32_t *handle)
{
  int flags, fd;
  switch (mode) {
  case 0: flags = O_RDONLY; break;
  case 1: flags = O_RDWR; break;
  default: flags = O_CREAT | O_TRUNC | O_RDWR; break;
  }
  fd = open(name, flags, 0664);
  if (fd < 0) return errno;
  *handle = fd;
  return 0;
}

int32_t PlatformClose(int32_t fd) NAME("close");
int32_t PlatformClose(int32_t fd) { return close(fd) < 0 ? errno : 0; }

int32_t PlatformRead(int32_t fd, void *buffer, int64_t length, int64_t *count) NAME("read");
int32_t PlatformRead(int32_t fd, void *buffer, int64_t length, int64_t *count)
{
  ssize_t n;
  *count = 0;
  if (length <= 0) return 0;
  n = read(fd, buffer, (size_t)length);
  if (n < 0) return errno;
  *count = n;
  return 0;
}

/* Writes all length bytes, in as many write calls as it takes (voc's makes
   one, and loses the rest of a short write). */
int32_t PlatformWrite(int32_t fd, const void *buffer, int64_t length) NAME("write");
int32_t PlatformWrite(int32_t fd, const void *buffer, int64_t length)
{
  const char *p = buffer;
  ssize_t n;
  while (length > 0) {
    n = write(fd, p, (size_t)length);
    if (n < 0) {
      if (errno == EINTR) continue;
      return errno;
    }
    p += n; length -= n;
  }
  return 0;
}

int32_t PlatformSync(int32_t fd) NAME("sync");
int32_t PlatformSync(int32_t fd) { return fsync(fd) < 0 ? errno : 0; }

/* whence 0, 1 and 2 are SEEK_SET, SEEK_CUR and SEEK_END. */
int32_t PlatformSeek(int32_t fd, int64_t offset, int32_t whence) NAME("seek");
int32_t PlatformSeek(int32_t fd, int64_t offset, int32_t whence)
{
  int w = whence == 1 ? SEEK_CUR : whence == 2 ? SEEK_END : SEEK_SET;
  return lseek(fd, (off_t)offset, w) < 0 ? errno : 0;
}

int32_t PlatformTruncate(int32_t fd, int64_t length) NAME("truncate");
int32_t PlatformTruncate(int32_t fd, int64_t length)
{
  return ftruncate(fd, (off_t)length) < 0 ? errno : 0;
}

static void StatFields(const struct stat *s, int64_t *volume, int64_t *index, int64_t *mtime, int64_t *size)
{
  *volume = (int64_t)s->st_dev;
  *index = (int64_t)s->st_ino;
  *mtime = (int64_t)s->st_mtime;
  *size = (int64_t)s->st_size;
}

/* The device, inode, modification time (seconds since 1970) and size of
   the open file fd. */
int32_t PlatformFileStatus(int32_t fd, int64_t *volume, int64_t *index, int64_t *mtime, int64_t *size) NAME("file-status");
int32_t PlatformFileStatus(int32_t fd, int64_t *volume, int64_t *index, int64_t *mtime, int64_t *size)
{
  struct stat s;
  if (fstat(fd, &s) < 0) return errno;
  StatFields(&s, volume, index, mtime, size);
  return 0;
}

/* The same of the file name. */
int32_t PlatformNameStatus(const char *name, int64_t *volume, int64_t *index, int64_t *mtime, int64_t *size) NAME("name-status");
int32_t PlatformNameStatus(const char *name, int64_t *volume, int64_t *index, int64_t *mtime, int64_t *size)
{
  struct stat s;
  if (stat(name, &s) < 0) return errno;
  StatFields(&s, volume, index, mtime, size);
  return 0;
}

/* Whether name is a directory (PLAN.md Phase 16 step 4): S_ISDIR is a
   macro of the system's headers. */
int32_t PlatformIsDirectory(const char *name) NAME("is-directory");
int32_t PlatformIsDirectory(const char *name)
{
  struct stat s;
  return stat(name, &s) == 0 && S_ISDIR(s.st_mode);
}

/* Makes the directory name, readable, writable and searchable by all but
   what the umask takes away: 0 or the errno value. mkdir's mode_t is
   16 bits on FreeBSD, 32 elsewhere. */
int32_t PlatformMakeDirectory(const char *name) NAME("make-directory");
int32_t PlatformMakeDirectory(const char *name)
{
  return mkdir(name, 0777) < 0 ? errno : 0;
}

/* Sets the access and modification times of the file name to the local
   time given (month 1..12), as voc's: EINVAL if mktime cannot represent
   it. */
int32_t PlatformSetFileTime(const char *name, int64_t year, int64_t month, int64_t day,
                            int64_t hour, int64_t minute, int64_t second) NAME("set-file-time");
int32_t PlatformSetFileTime(const char *name, int64_t year, int64_t month, int64_t day,
                            int64_t hour, int64_t minute, int64_t second)
{
  struct tm t;
  struct utimbuf times;
  memset(&t, 0, sizeof t);
  t.tm_year = (int)year - 1900; t.tm_mon = (int)month - 1; t.tm_mday = (int)day;
  t.tm_hour = (int)hour; t.tm_min = (int)minute; t.tm_sec = (int)second;
  t.tm_isdst = -1;
  times.modtime = mktime(&t);
  if (times.modtime == (time_t)-1) return EINVAL;
  times.actime = times.modtime;
  return utime(name, &times) < 0 ? errno : 0;
}

/* The time now, in seconds and microseconds since 1970. */
void PlatformTimeOfDay(int64_t *seconds, int64_t *microseconds) NAME("time-of-day");
void PlatformTimeOfDay(int64_t *seconds, int64_t *microseconds)
{
  struct timeval tv;
  gettimeofday(&tv, 0);
  *seconds = (int64_t)tv.tv_sec;
  *microseconds = (int64_t)tv.tv_usec;
}

/* The local time of seconds since 1970, as struct tm has it: the year
   since 1900, the month 0..11. All zero if localtime cannot say. */
void PlatformLocalTime(int64_t seconds, int64_t *year, int64_t *month, int64_t *day,
                       int64_t *hour, int64_t *minute, int64_t *second) NAME("local-time");
void PlatformLocalTime(int64_t seconds, int64_t *year, int64_t *month, int64_t *day,
                       int64_t *hour, int64_t *minute, int64_t *second)
{
  time_t t = (time_t)seconds;
  struct tm *tm = localtime(&t);
  if (tm == 0) { *year = *month = *day = *hour = *minute = *second = 0; return; }
  *year = tm->tm_year; *month = tm->tm_mon; *day = tm->tm_mday;
  *hour = tm->tm_hour; *minute = tm->tm_min; *second = tm->tm_sec;
}

/* Sleeps for milliseconds, the whole time even when a signal interrupts
   it (voc's sleeps once). */
void PlatformDelay(int64_t milliseconds) NAME("delay");
void PlatformDelay(int64_t milliseconds)
{
  struct timespec request, remaining;
  if (milliseconds <= 0) return;
  request.tv_sec = (time_t)(milliseconds / 1000);
  request.tv_nsec = (long)(milliseconds % 1000) * 1000000L;
  while (nanosleep(&request, &remaining) < 0 && errno == EINTR) request = remaining;
}

/* Makes handler the handler of the signal number, which is called with the
   signal's number; system calls it interrupts are restarted, as with
   signal() on all four systems. */
void PlatformSetHandler(int32_t number, void (*handler)(int32_t)) NAME("set-handler");
void PlatformSetHandler(int32_t number, void (*handler)(int32_t))
{
  struct sigaction action;
  memset(&action, 0, sizeof action);
  action.sa_handler = (void (*)(int))handler;
  sigemptyset(&action.sa_mask);
  action.sa_flags = SA_RESTART;
  sigaction(number, &action, 0);
}
