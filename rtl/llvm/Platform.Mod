MODULE Platform;

  (* The operating-system services of voc's Platform module
     (src/runtime/Platformunix.Mod), with its interface, so that a program
     written against voc's compiles unchanged: files by handle, file
     identities and times, the clock, the environment, the working
     directory, signal handlers, memory from the system, running a shell
     command and ending the process. PLAN.md Phase 10 step 2 brought what
     poc's own driver needs (Chdir, CWD, GetEnv, PID, System, Unlink, Exit);
     Phase 12 step 5a the rest.

     Two parts. What is the same on Linux, NetBSD, OpenBSD and FreeBSD -
     the C names chdir, exit, free, getcwd, getenv, getpid, isatty, malloc,
     rename, system, unlink and their arguments - is declared here as
     external ["C"] procedures. What is not - open's flags, errno and its
     values, struct stat, the clock, signals - is in Platform.c beside this
     file, compiled by clang for the target from the system's own headers
     (decided with the user 2026-10-02), under names that start with
     "Platform.-". Its header says why each is there.

     An ErrorCode is 0 for success, otherwise the errno value of the call
     that failed, as voc's: so its numbers differ between the systems, and
     a program tests them with Absent, Inaccessible, TooManyFiles and the
     others rather than comparing them with numbers.

     Where this differs from voc's (the numbers are those of vishap-bugs,
     ~/Repos/Oberon/vishap-bugs):

     - PID is never negative: a pid that does not fit an INTEGER (16 bits
       under -O2) is reduced modulo 2^15, so the temporary file names built
       from it stay readable (61).
     - Write writes everything, in as many write calls as it takes, and
       Delay sleeps the whole time even when a signal interrupts it (59,
       60).
     - getEnv returns FALSE for a name with no 0X in it (below). It copies
       at most what val holds, as voc's does (D6).
     - The C type `int` is written SYSTEM.INT32 in the external
       declarations here and in Console, Files, In, Out, Math and MathL:
       exactly four bytes under -O2 and -OC alike, as LONGINT (eight bytes
       under -OC) is not - which is wrong at once on a 32-bit target, whose
       calling convention puts every argument on the stack at its own width.
       (voc's LONGINT there does no harm: its declarations are C macros,
       D8.)

     A string handed to a C function must end in 0X within its array; one
     that does not is treated as naming nothing: the procedure fails with
     ENOENT's error code where it returns one (GetEnv finds no variable,
     System runs nothing and returns -1). *)

  IMPORT SYSTEM;

  CONST
    (* the handles of standard input, output and error *)
    StdIn* = 0;
    StdOut* = 1;
    StdErr* = 2;

    cwdLength = 256;

    (* Platform.c's modes of opening a file *)
    openReadOnly = 0;
    openReadWrite = 1;
    openNew = 2;

    (* Platform.c's classes of errno values, one for each error test *)
    tooManyFilesClass = 0;
    absentClass = 1;
    differentFilesystemsClass = 2;
    inaccessibleClass = 3;
    timedOutClass = 4;
    connectionFailedClass = 5;
    interruptedClass = 6;

    (* the signals voc's handlers are for: the same numbers on every
       system *)
    interruptSignal = 2;
    quitSignal = 3;
    badInstructionSignal = 4;

  TYPE
    SignalHandler = PROCEDURE (signal: SYSTEM.INT32);

    (* 0, or the errno value of a call that failed; an open file's
       descriptor *)
    ErrorCode* = INTEGER;
    FileHandle* = LONGINT;

    (* which file a file is, and when it was last modified *)
    FileIdentity* = RECORD
      volume: LONGINT; (* the device *)
      index: LONGINT; (* the inode *)
      mtime: LONGINT (* the time the file was last modified, in seconds since 1970 *)
    END;

  VAR
    (* whether the machine stores the least significant byte first; the
       process id; the working directory, as at the start and after Chdir; the
       whence values for Seek *)
    LittleEndian-: BOOLEAN;
    PID-: INTEGER;
    CWD-: ARRAY cwdLength OF CHAR;
    SeekSet-, SeekCur-, SeekEnd-: INTEGER;
    NL-: ARRAY 3 OF CHAR; (* the line ending: LF on every system here *)
    timeStart: HUGEINT; (* Time's zero, in milliseconds since 1970 *)

  PROCEDURE ["C", "getenv"] CGetEnv(name: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "getpid"] CGetPid(): SYSTEM.INT32;
  PROCEDURE ["C", "chdir"] CChdir(path: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "getcwd"] CGetCwd(buffer, size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "system"] CSystem(command: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "unlink"] CUnlink(path: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "rename"] CRename(old, new: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "exit"] CExit(code: SYSTEM.INT32);
  PROCEDURE ["C", "malloc"] CMalloc(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "free"] CFree(address: SYSTEM.ADDRESS);
  PROCEDURE ["C", "isatty"] CIsATTY(fd: SYSTEM.INT32): SYSTEM.INT32;

  (* Platform.c *)
  PROCEDURE ["C", "Platform.-errno"] CErrno(): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-no-such-file"] CNoSuchFile(): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-is-error"] CIsError(class, e: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-max-name-length"] CMaxNameLength(): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-max-path-length"] CMaxPathLength(): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-open"] COpen(name: SYSTEM.ADDRESS; mode: SYSTEM.INT32; handle: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-close"] CClose(fd: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-read"] CRead(fd: SYSTEM.INT32; buffer: SYSTEM.ADDRESS; length: SYSTEM.INT64;
                                          count: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-write"] CWrite(fd: SYSTEM.INT32; buffer: SYSTEM.ADDRESS; length: SYSTEM.INT64): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-sync"] CSync(fd: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-seek"] CSeek(fd: SYSTEM.INT32; offset: SYSTEM.INT64; whence: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-truncate"] CTruncate(fd: SYSTEM.INT32; length: SYSTEM.INT64): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-file-status"] CFileStatus(fd: SYSTEM.INT32; volume, index, mtime, size: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-name-status"] CNameStatus(name, volume, index, mtime, size: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-set-file-time"] CSetFileTime(name: SYSTEM.ADDRESS;
                                                           year, month, day, hour, minute, second: SYSTEM.INT64): SYSTEM.INT32;
  PROCEDURE ["C", "Platform.-time-of-day"] CTimeOfDay(seconds, microseconds: SYSTEM.ADDRESS);
  PROCEDURE ["C", "Platform.-local-time"] CLocalTime(seconds: SYSTEM.INT64;
                                                     year, month, day, hour, minute, second: SYSTEM.ADDRESS);
  PROCEDURE ["C", "Platform.-delay"] CDelay(milliseconds: SYSTEM.INT64);
  PROCEDURE ["C", "Platform.-set-handler"] CSetHandler(signal: SYSTEM.INT32; handler: SYSTEM.ADDRESS);

  (* Whether s has a terminating 0X inside its array. *)
  PROCEDURE Terminated(VAR s: ARRAY OF CHAR): BOOLEAN;
    VAR k: LONGINT;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k < LEN(s)
  END Terminated;

  (* The error code of a name that is not terminated: the system's own
     for a file that is not there, ENOENT *)
  PROCEDURE NoSuchName(): ErrorCode;
  BEGIN
    RETURN SYSTEM.VAL(ErrorCode, CNoSuchFile())
  END NoSuchName;

  (* The error code of a failed call made through Platform.c, which returns
     it as a C int *)
  PROCEDURE Code(e: SYSTEM.INT32): ErrorCode;
  BEGIN
    RETURN SYSTEM.VAL(ErrorCode, e) (* an errno value fits 16 bits *)
  END Code;

  (* The error code of the last call that failed. *)
  PROCEDURE Error*(): ErrorCode;
  BEGIN
    RETURN Code(CErrno())
  END Error;

  (* Error tests: whether the error code e means too many open files, no
     such directory, a rename across file systems, no permission, no such
     file, a time-out, a refused or failed connection, or a call
     interrupted by a signal. NoSuchDirectory and Absent test the same
     codes. *)
  PROCEDURE TooManyFiles*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(tooManyFilesClass, e) # 0
  END TooManyFiles;

  PROCEDURE NoSuchDirectory*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(absentClass, e) # 0
  END NoSuchDirectory;

  PROCEDURE DifferentFilesystems*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(differentFilesystemsClass, e) # 0
  END DifferentFilesystems;

  PROCEDURE Inaccessible*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(inaccessibleClass, e) # 0
  END Inaccessible;

  PROCEDURE Absent*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(absentClass, e) # 0
  END Absent;

  PROCEDURE TimedOut*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(timedOutClass, e) # 0
  END TimedOut;

  PROCEDURE ConnectionFailed*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(connectionFailedClass, e) # 0
  END ConnectionFailed;

  PROCEDURE Interrupted*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN CIsError(interruptedClass, e) # 0
  END Interrupted;

  (* File and path name length limits: NAME_MAX and PATH_MAX *)
  PROCEDURE MaxNameLength*(): INTEGER;
  BEGIN RETURN SYSTEM.VAL(INTEGER, CMaxNameLength())
  END MaxNameLength;

  PROCEDURE MaxPathLength*(): INTEGER;
  BEGIN RETURN SYSTEM.VAL(INTEGER, CMaxPathLength())
  END MaxPathLength;

  (* Memory from the system, outside the collected heap: malloc and free *)
  PROCEDURE OSAllocate*(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  BEGIN RETURN CMalloc(size)
  END OSAllocate;

  PROCEDURE OSFree*(address: SYSTEM.ADDRESS);
  BEGIN CFree(address)
  END OSFree;

  (* The environment *)

  (* The value of the environment variable var in val, cut short if val is
     too small for it; FALSE, and val unchanged, when there is no such
     variable. *)
  PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
    VAR text: SYSTEM.ADDRESS; k: LONGINT; ch: CHAR;
  BEGIN
    IF ~Terminated(var) THEN RETURN FALSE END;
    text := CGetEnv(SYSTEM.ADR(var));
    IF text = 0 THEN RETURN FALSE END;
    IF LEN(val) > 0 THEN
      k := 0;
      SYSTEM.GET(text, ch);
      WHILE (ch # 0X) & (k < LEN(val) - 1) DO
        val[k] := ch;
        INC(k);
        SYSTEM.GET(text + k, ch)
      END;
      val[k] := 0X
    END;
    RETURN TRUE
  END getEnv;

  (* The value of the environment variable var in val, cut short if val is
     too small for it; "" when there is no such variable (or it is empty).
     Same as voc's. *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
  BEGIN
    IF ~getEnv(var, val) & (LEN(val) > 0) THEN val[0] := 0X END
  END GetEnv;

  (* Signals: handler is called with the signal's number when the process
     gets it (SIGINT, SIGQUIT, SIGILL). A handler stays in place until
     another replaces it. Its type, SignalHandler, is not exported (as in
     voc): PROCEDURE (signal: SYSTEM.INT32). *)
  PROCEDURE SetInterruptHandler*(handler: SignalHandler);
  BEGIN CSetHandler(interruptSignal, SYSTEM.VAL(SYSTEM.ADDRESS, handler))
  END SetInterruptHandler;

  PROCEDURE SetQuitHandler*(handler: SignalHandler);
  BEGIN CSetHandler(quitSignal, SYSTEM.VAL(SYSTEM.ADDRESS, handler))
  END SetQuitHandler;

  PROCEDURE SetBadInstructionHandler*(handler: SignalHandler);
  BEGIN CSetHandler(badInstructionSignal, SYSTEM.VAL(SYSTEM.ADDRESS, handler))
  END SetBadInstructionHandler;

  (* Time *)

  (* voc's clock format, the Oberon system's: d holds the year modulo 100
     (bits 9 and up), the month 1..12 (bits 5-8) and the day (bits 0-4); t
     the hour (bits 12 and up), the minute (bits 6-11) and the second (bits
     0-5). year is since 1900 and month 0..11, as struct tm has them. *)
  PROCEDURE ClockOf(year, month, day, hour, minute, second: HUGEINT; VAR t, d: LONGINT);
  BEGIN
    d := SYSTEM.VAL(LONGINT, ASH(year MOD 100, 9) + ASH(month + 1, 5) + day);
    t := SYSTEM.VAL(LONGINT, ASH(hour, 12) + ASH(minute, 6) + second)
  END ClockOf;

  (* t and d in ClockOf's format for seconds since 1970, in local time *)
  PROCEDURE LocalClock(seconds: HUGEINT; VAR t, d: LONGINT);
    VAR year, month, day, hour, minute, second: SYSTEM.INT64;
  BEGIN
    CLocalTime(seconds, SYSTEM.ADR(year), SYSTEM.ADR(month), SYSTEM.ADR(day),
               SYSTEM.ADR(hour), SYSTEM.ADR(minute), SYSTEM.ADR(second));
    ClockOf(year, month, day, hour, minute, second, t, d)
  END LocalClock;

  (* The local time now, in the Oberon system's format: d holds the year
     modulo 100 (bits 9 and up), the month 1..12 (bits 5-8) and the day
     (bits 0-4); t the hour (bits 12 and up), the minute (bits 6-11) and
     the second (bits 0-5). *)
  PROCEDURE GetClock*(VAR t, d: LONGINT);
    VAR seconds, microseconds: SYSTEM.INT64;
  BEGIN
    CTimeOfDay(SYSTEM.ADR(seconds), SYSTEM.ADR(microseconds));
    LocalClock(seconds, t, d)
  END GetClock;

  (* The time now, in seconds and microseconds since 1970 (the seconds
     wrap in 2038 under -O2, where a LONGINT has 32 bits, as voc's). *)
  PROCEDURE GetTimeOfDay*(VAR sec, usec: LONGINT);
    VAR seconds, microseconds: SYSTEM.INT64;
  BEGIN
    CTimeOfDay(SYSTEM.ADR(seconds), SYSTEM.ADR(microseconds));
    sec := SYSTEM.VAL(LONGINT, seconds); usec := SYSTEM.VAL(LONGINT, microseconds)
  END GetTimeOfDay;

  PROCEDURE Milliseconds(): HUGEINT;
    VAR seconds, microseconds: SYSTEM.INT64;
  BEGIN
    CTimeOfDay(SYSTEM.ADR(seconds), SYSTEM.ADR(microseconds));
    RETURN seconds * 1000 + microseconds DIV 1000
  END Milliseconds;

  (* The milliseconds since the program started, modulo 7FFFFFFFH. *)
  PROCEDURE Time*(): LONGINT;
  BEGIN
    RETURN SYSTEM.VAL(LONGINT, (Milliseconds() - timeStart) MOD 7FFFFFFFH)
  END Time;

  (* Sleeps for ms milliseconds. *)
  PROCEDURE Delay*(ms: LONGINT);
  BEGIN CDelay(ms)
  END Delay;

  (* Running a command *)

  (* Runs cmd with the shell (/bin/sh -c), waits for it, and returns the
     wait status: 0 when the command succeeded, otherwise the exit code
     times 256 (plus the signal number if it was killed), or -1 if no shell
     could be run. Narrowed to an INTEGER as voc's is, so a large status
     may wrap; it does not wrap to 0. *)
  PROCEDURE System*(cmd: ARRAY OF CHAR): INTEGER;
    VAR status: LONGINT;
  BEGIN
    IF ~Terminated(cmd) THEN RETURN -1 END;
    status := CSystem(SYSTEM.ADR(cmd)); (* a C int, widened to LONGINT for SHORT *)
    RETURN SHORT(status)
  END System;

  (* Files by handle *)

  PROCEDURE Open(VAR n: ARRAY OF CHAR; mode: SYSTEM.INT32; VAR h: FileHandle): ErrorCode;
    VAR fd, e: SYSTEM.INT32;
  BEGIN
    IF ~Terminated(n) THEN RETURN NoSuchName() END;
    e := COpen(SYSTEM.ADR(n), mode, SYSTEM.ADR(fd));
    IF e = 0 THEN h := fd END;
    RETURN Code(e)
  END Open;

  (* Opens the file n to read. *)
  PROCEDURE OldRO*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
  BEGIN RETURN Open(n, openReadOnly, h)
  END OldRO;

  (* Opens the file n to read and write. *)
  PROCEDURE OldRW*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
  BEGIN RETURN Open(n, openReadWrite, h)
  END OldRW;

  (* Creates the file n, or empties it if it is there, to read and write. *)
  PROCEDURE New*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
  BEGIN RETURN Open(n, openNew, h)
  END New;

  (* Closes h. *)
  PROCEDURE Close*(h: FileHandle): ErrorCode;
  BEGIN RETURN Code(CClose(SYSTEM.VAL(SYSTEM.INT32, h)))
  END Close;

  (* Whether h is a terminal. *)
  PROCEDURE IsConsole*(h: FileHandle): BOOLEAN;
  BEGIN RETURN CIsATTY(SYSTEM.VAL(SYSTEM.INT32, h)) # 0
  END IsConsole;

  (* Reads at most l bytes from h to the address p; n is how many it read,
     0 at the end of the file. *)
  PROCEDURE Read*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT; VAR n: LONGINT): ErrorCode;
    VAR count: SYSTEM.INT64; e: SYSTEM.INT32;
  BEGIN
    e := CRead(SYSTEM.VAL(SYSTEM.INT32, h), p, l, SYSTEM.ADR(count));
    n := SYSTEM.VAL(LONGINT, count);
    RETURN Code(e)
  END Read;

  (* Reads at most LEN(b) bytes from h into b; n is how many it read. *)
  PROCEDURE ReadBuf*(h: FileHandle; VAR b: ARRAY OF SYSTEM.BYTE; VAR n: LONGINT): ErrorCode;
  BEGIN RETURN Read(h, SYSTEM.ADR(b), LEN(b), n)
  END ReadBuf;

  (* Writes the l bytes at the address p to h. *)
  PROCEDURE Write*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT): ErrorCode;
  BEGIN RETURN Code(CWrite(SYSTEM.VAL(SYSTEM.INT32, h), p, l))
  END Write;

  (* Writes what the system holds of h to the disk. *)
  PROCEDURE Sync*(h: FileHandle): ErrorCode;
  BEGIN RETURN Code(CSync(SYSTEM.VAL(SYSTEM.INT32, h)))
  END Sync;

  (* Moves h's position to offset from whence: SeekSet (the start),
     SeekCur (the position) or SeekEnd (the end). *)
  PROCEDURE Seek*(h: FileHandle; offset: LONGINT; whence: INTEGER): ErrorCode;
  BEGIN RETURN Code(CSeek(SYSTEM.VAL(SYSTEM.INT32, h), offset, whence))
  END Seek;

  (* Cuts h, or extends it with zeros, to l bytes. *)
  PROCEDURE Truncate*(h: FileHandle; l: LONGINT): ErrorCode;
  BEGIN RETURN Code(CTruncate(SYSTEM.VAL(SYSTEM.INT32, h), l))
  END Truncate;

  (* The length of h in l. *)
  PROCEDURE Size*(h: FileHandle; VAR l: LONGINT): ErrorCode;
    VAR volume, index, mtime, size: SYSTEM.INT64; e: SYSTEM.INT32;
  BEGIN
    e := CFileStatus(SYSTEM.VAL(SYSTEM.INT32, h), SYSTEM.ADR(volume), SYSTEM.ADR(index),
                     SYSTEM.ADR(mtime), SYSTEM.ADR(size));
    IF e = 0 THEN l := SYSTEM.VAL(LONGINT, size) END;
    RETURN Code(e)
  END Size;

  (* File identities: which file it is, and when it was last modified *)

  PROCEDURE SetIdentity(VAR identity: FileIdentity; volume, index, mtime: SYSTEM.INT64);
  BEGIN
    identity.volume := SYSTEM.VAL(LONGINT, volume);
    identity.index := SYSTEM.VAL(LONGINT, index);
    identity.mtime := SYSTEM.VAL(LONGINT, mtime)
  END SetIdentity;

  (* The identity of the open file h, or of the file named n *)
  PROCEDURE Identify*(h: FileHandle; VAR identity: FileIdentity): ErrorCode;
    VAR volume, index, mtime, size: SYSTEM.INT64; e: SYSTEM.INT32;
  BEGIN
    e := CFileStatus(SYSTEM.VAL(SYSTEM.INT32, h), SYSTEM.ADR(volume), SYSTEM.ADR(index),
                     SYSTEM.ADR(mtime), SYSTEM.ADR(size));
    IF e = 0 THEN SetIdentity(identity, volume, index, mtime) END;
    RETURN Code(e)
  END Identify;

  PROCEDURE IdentifyByName*(n: ARRAY OF CHAR; VAR identity: FileIdentity): ErrorCode;
    VAR volume, index, mtime, size: SYSTEM.INT64; e: SYSTEM.INT32;
  BEGIN
    IF ~Terminated(n) THEN RETURN NoSuchName() END;
    e := CNameStatus(SYSTEM.ADR(n), SYSTEM.ADR(volume), SYSTEM.ADR(index),
                     SYSTEM.ADR(mtime), SYSTEM.ADR(size));
    IF e = 0 THEN SetIdentity(identity, volume, index, mtime) END;
    RETURN Code(e)
  END IdentifyByName;

  (* Whether i1 and i2 are the same file (device and inode); whether they
     were last modified at the same time (in seconds); target's time made
     source's (in the identity, not the file) *)
  PROCEDURE SameFile*(i1, i2: FileIdentity): BOOLEAN;
  BEGIN RETURN (i1.index = i2.index) & (i1.volume = i2.volume)
  END SameFile;

  PROCEDURE SameFileTime*(i1, i2: FileIdentity): BOOLEAN;
  BEGIN RETURN i1.mtime = i2.mtime
  END SameFileTime;

  PROCEDURE SetMTime*(VAR target: FileIdentity; source: FileIdentity);
  BEGIN target.mtime := source.mtime
  END SetMTime;

  (* i's modification time, in local time in GetClock's format. *)
  PROCEDURE MTimeAsClock*(i: FileIdentity; VAR t, d: LONGINT);
  BEGIN LocalClock(i.mtime, t, d)
  END MTimeAsClock;

  (* Sets the file n's modification (and access) time to the local time
     given, month 1..12. *)
  PROCEDURE SetFileMTime*(VAR n: ARRAY OF CHAR; year, month, day, hour, minute, second: LONGINT): ErrorCode;
  BEGIN
    IF ~Terminated(n) THEN RETURN NoSuchName() END;
    RETURN Code(CSetFileTime(SYSTEM.ADR(n), year, month, day, hour, minute, second))
  END SetFileMTime;

  (* Files by name *)

  (* Deletes the file n. *)
  PROCEDURE Unlink*(VAR n: ARRAY OF CHAR): ErrorCode;
  BEGIN
    IF ~Terminated(n) THEN RETURN NoSuchName() END;
    IF CUnlink(SYSTEM.ADR(n)) < 0 THEN RETURN Error() END;
    RETURN 0
  END Unlink;

  (* Renames the file o to n, replacing any file n. *)
  PROCEDURE Rename*(VAR o, n: ARRAY OF CHAR): ErrorCode;
  BEGIN
    IF ~Terminated(o) OR ~Terminated(n) THEN RETURN NoSuchName() END;
    IF CRename(SYSTEM.ADR(o), SYSTEM.ADR(n)) < 0 THEN RETURN Error() END;
    RETURN 0
  END Rename;

  (* The working directory *)

  (* Reads the working directory into CWD; "" if the system cannot say
     (a path longer than CWD holds, for one). *)
  PROCEDURE RefreshCWD(): BOOLEAN;
  BEGIN
    IF CGetCwd(SYSTEM.ADR(CWD), SYSTEM.VAL(SYSTEM.ADDRESS, LEN(CWD))) = 0 THEN
      CWD[0] := 0X;
      RETURN FALSE
    END;
    RETURN TRUE
  END RefreshCWD;

  (* Makes the directory n the working directory, and updates CWD. *)
  PROCEDURE Chdir*(VAR n: ARRAY OF CHAR): ErrorCode;
  BEGIN
    IF ~Terminated(n) THEN RETURN NoSuchName() END;
    IF (CChdir(SYSTEM.ADR(n)) < 0) OR ~RefreshCWD() THEN RETURN Error() END;
    RETURN 0
  END Chdir;

  (* Ending the process *)

  (* Ends the process with status code, flushing C's buffered output first
     (voc's Platform.Exit, whose parameter is a LONGINT too). *)
  PROCEDURE Exit*(code: LONGINT);
  BEGIN
    CExit(SYSTEM.VAL(SYSTEM.INT32, code))
  END Exit;

  PROCEDURE InitProcessId;
    VAR id: LONGINT;
  BEGIN
    id := CGetPid();
    IF id > MAX(INTEGER) THEN id := id MOD (LONG(MAX(INTEGER)) + 1) END;
    PID := SHORT(id)
  END InitProcessId;

  PROCEDURE TestLittleEndian;
    VAR i: INTEGER;
  BEGIN
    i := 1; SYSTEM.GET(SYSTEM.ADR(i), LittleEndian)
  END TestLittleEndian;

BEGIN
  TestLittleEndian;
  timeStart := Milliseconds();
  InitProcessId;
  IF ~RefreshCWD() THEN CWD[0] := 0X END;
  SeekSet := 0; SeekCur := 1; SeekEnd := 2;
  NL[0] := 0AX; NL[1] := 0X
END Platform.
