MODULE Platform;

  (* PLAN.md Phase 10 step 2: the operating-system services poc's own
     driver uses, under the names and signatures of voc's Platform module
     (src/runtime/Platformunix.Mod), so poc's source compiles unchanged
     against either one: the current directory (Chdir, CWD), environment
     variables (GetEnv), the process id (PID), deleting a file (Unlink)
     and running a shell command (System). Each is a thin layer over one
     libc call, made through an external ["C"] procedure. Only what poc
     needs is here; voc's file-handle, clock and signal procedures are not.
     (Files.Mod, step 3, will bring what it needs of them.)

     Every libc name used - chdir, getcwd, getenv, getpid, system, unlink -
     is the same on Linux, NetBSD, OpenBSD and FreeBSD.

     Where this differs from voc's:

     - An error code is 0 for success and -1 for failure. voc's is the
       errno value (2 for a missing file), but errno is a macro reaching a
       per-thread variable through a function whose name differs between
       the systems (__errno_location on Linux, __error on FreeBSD,
       __errno on NetBSD and OpenBSD), and there is no conditional
       compilation to pick one. Nothing in poc looks at more than "is it
       0".
     - PID is never negative. voc keeps it in an INTEGER, which under its
       default 16-bit size model wraps a pid above 32767, possibly to a
       negative number; here the pid is reduced modulo 2^15 first when it
       does not fit, so the temporary file names built from it stay
       readable. (It stays whole under a size model with a 32-bit INTEGER.)
     - The C type `int` is written LONGINT in the external declarations,
       which is what it is under the -O2 size model, the only one poc
       generates code for so far. SYSTEM.INT32 exists (step 7) but is only an
       alias of LONGINT, so it would not be right under -OC either; they
       should move to a real fixed-width INT32 when there is one
       (PLAN.md's Phase 11 table).

     A string handed to a C function must end in 0X within its array; one
     that does not is treated as naming nothing (Chdir and Unlink fail,
     GetEnv finds no variable, System runs nothing and reports failure). *)

  IMPORT SYSTEM;

  CONST
    failure = -1;
    cwdLength = 256;

  TYPE
    ErrorCode* = INTEGER;

  VAR
    PID-: INTEGER;
    CWD-: ARRAY cwdLength OF CHAR;

  PROCEDURE ["C", "getenv"] CGetEnv(name: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "getpid"] CGetPid(): LONGINT;
  PROCEDURE ["C", "chdir"] CChdir(path: SYSTEM.ADDRESS): LONGINT;
  PROCEDURE ["C", "getcwd"] CGetCwd(buffer, size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "system"] CSystem(command: SYSTEM.ADDRESS): LONGINT;
  PROCEDURE ["C", "unlink"] CUnlink(path: SYSTEM.ADDRESS): LONGINT;

  (* Whether s has a terminating 0X inside its array. *)
  PROCEDURE Terminated(s: ARRAY OF CHAR): BOOLEAN;
    VAR k: LONGINT;
  BEGIN
    k := 0;
    WHILE (k < LEN(s)) & (s[k] # 0X) DO INC(k) END;
    RETURN k < LEN(s)
  END Terminated;

  (* Reads the working directory into CWD; "" if the system cannot say
     (a path longer than CWD holds, for one). *)
  PROCEDURE RefreshCWD(): BOOLEAN;
  BEGIN
    IF CGetCwd(SYSTEM.ADR(CWD), LEN(CWD)) = 0 THEN
      CWD[0] := 0X;
      RETURN FALSE
    END;
    RETURN TRUE
  END RefreshCWD;

  (* Makes the directory n the working directory, and updates CWD. *)
  PROCEDURE Chdir*(VAR n: ARRAY OF CHAR): ErrorCode;
  BEGIN
    IF ~Terminated(n) THEN RETURN failure END;
    IF CChdir(SYSTEM.ADR(n)) < 0 THEN RETURN failure END;
    IF ~RefreshCWD() THEN RETURN failure END;
    RETURN 0
  END Chdir;

  (* The value of the environment variable var in val, cut short if val is
     too small for it; "" when there is no such variable (or it is empty).
     Same as voc's. *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
    VAR text: SYSTEM.ADDRESS; k: LONGINT; ch: CHAR;
  BEGIN
    IF LEN(val) = 0 THEN RETURN END;
    val[0] := 0X;
    IF ~Terminated(var) THEN RETURN END;
    text := CGetEnv(SYSTEM.ADR(var));
    IF text = 0 THEN RETURN END;
    k := 0;
    SYSTEM.GET(text, ch);
    WHILE (ch # 0X) & (k < LEN(val) - 1) DO
      val[k] := ch;
      INC(k);
      SYSTEM.GET(text + k, ch)
    END;
    val[k] := 0X
  END GetEnv;

  (* Runs cmd with the shell (/bin/sh -c), waits for it, and returns the
     wait status: 0 when the command succeeded, otherwise the exit code
     times 256 (plus the signal number if it was killed), or -1 if no shell
     could be run. Narrowed to an INTEGER as voc's is, so a large status
     may wrap; it does not wrap to 0. *)
  PROCEDURE System*(cmd: ARRAY OF CHAR): INTEGER;
  BEGIN
    IF ~Terminated(cmd) THEN RETURN failure END;
    RETURN SHORT(CSystem(SYSTEM.ADR(cmd)))
  END System;

  (* Deletes the file n. *)
  PROCEDURE Unlink*(VAR n: ARRAY OF CHAR): ErrorCode;
  BEGIN
    IF ~Terminated(n) THEN RETURN failure END;
    IF CUnlink(SYSTEM.ADR(n)) < 0 THEN RETURN failure END;
    RETURN 0
  END Unlink;

  PROCEDURE InitProcessId;
    VAR id: LONGINT;
  BEGIN
    id := CGetPid();
    IF id > MAX(INTEGER) THEN id := id MOD (LONG(MAX(INTEGER)) + 1) END;
    PID := SHORT(id)
  END InitProcessId;

BEGIN
  InitProcessId;
  IF ~RefreshCWD() THEN CWD[0] := 0X END
END Platform.
