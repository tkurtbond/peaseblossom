MODULE Platform;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposals 3 to 8): the part of rtl/llvm/Platform.Mod's interface
     that poc's own source uses, for VAX/VMS, over the services
     rtl/vax/PocRtl.mar calls: GetEnv, Unlink, System, Exit, PID, CWD and
     NL, and step 4's MakePath, IsDirectory, MakeDirectory and
     pathSeparator, which rtl/llvm's Platform has too.

     A name is given to VMS as it is, so case does not matter in it, and a
     file name without a version means the highest one. RMS takes a file
     name of at most 255 characters, and $TRNLNM a logical name of at most
     255; a longer one names nothing here.

     An ErrorCode is 0 for success, otherwise the VMS status of the service
     that failed, its low word under -O2 (where an INTEGER is a word),
     which is never 0 for a status RMS returns: its severity and message
     number are there.

     The routines of PocRtl.mar return a longword in R0, which a
     declaration here takes as an INTEGER: the whole longword under -OC,
     its low word under -O2. A length, at most 1024, fits either. *)

  CONST
    (* what separates the directories of a list of them, such as
       POC_IMPORT_PATH's: "," on VMS, as a directory has ":" in it *)
    pathSeparator* = ",";

    nameLength = 256; (* a name and its 0X *)

  TYPE
    (* 0, or the status of a service that failed *)
    ErrorCode* = INTEGER;
    Name = ARRAY nameLength OF CHAR;

  VAR
    (* the process's identification, reduced modulo 2^15 under -O2, as
       rtl/llvm's is when it does not fit an INTEGER; the default device and
       directory, at the start; the line ending, LF, which a record's end
       stands for *)
    PID-: INTEGER;
    CWD-: ARRAY nameLength OF CHAR;
    NL-: ARRAY 3 OF CHAR;
    (* a name given to a service, and a value one gives back *)
    given, returned: Name;

  PROCEDURE ["VMS"] POC_TRNLNM(VAR name: Name; length, index: INTEGER; VAR value: Name; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_ERASE(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_PARSE(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_CREATE_DIRECTORY(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_DEFAULT_DIRECTORY(VAR value: Name; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_PROCESS_ID(): INTEGER;
  PROCEDURE ["VMS"] POC_HALT(code: INTEGER);

  (* s up to its 0X in given, and its length in length; FALSE if it is
     longer than a service takes *)
  PROCEDURE Fill(VAR s: ARRAY OF CHAR; VAR length: INTEGER): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO
      IF i = nameLength - 1 THEN RETURN FALSE END;
      given[i] := s[i]; INC(i)
    END;
    given[i] := 0X; length := SHORT(i);
    RETURN TRUE
  END Fill;

  (* ch appended to s, if s can hold it *)
  PROCEDURE AppendChar(VAR s: ARRAY OF CHAR; ch: CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
    IF i < LEN(s) - 1 THEN s[i] := ch; s[i + 1] := 0X END
  END AppendChar;

  (* the first count characters of returned appended to s, cut short if s
     cannot hold them *)
  PROCEDURE Append(VAR s: ARRAY OF CHAR; count: INTEGER);
    VAR k: INTEGER;
  BEGIN
    FOR k := 0 TO count - 1 DO AppendChar(s, returned[k]) END
  END Append;

  (* given, ended with ":" if it does not end with ":", "]" or ">": a
     directory, or a logical name that stands for one; FALSE if it is ""
     or there is no room *)
  PROCEDURE AsDirectory(VAR length: INTEGER): BOOLEAN;
    VAR last: CHAR;
  BEGIN
    IF length = 0 THEN RETURN FALSE END;
    last := given[length - 1];
    IF (last # ":") & (last # "]") & (last # ">") THEN
      IF length = nameLength - 1 THEN RETURN FALSE END;
      given[length] := ":"; INC(length); given[length] := 0X
    END;
    RETURN TRUE
  END AsDirectory;

  (* The environment *)

  (* The logical name var translated, in val, cut short if val is too
     small for it; "" when there is no such name. It is looked up as a file
     name's is (LNM$FILE_DEV: the process's table, the job's, the group's,
     the system's), ignoring case. A search list's equivalence strings are
     joined with ",", pathSeparator. *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
    VAR length, index, count: INTEGER;
  BEGIN
    IF LEN(val) = 0 THEN RETURN END;
    val[0] := 0X;
    IF Fill(var, length) & (length > 0) THEN
      index := 0;
      REPEAT
        count := POC_TRNLNM(given, length, index, returned, nameLength - 1);
        IF count >= 0 THEN
          IF index > 0 THEN AppendChar(val, pathSeparator) END;
          Append(val, count)
        END;
        INC(index)
      UNTIL count < 0
    END
  END GetEnv;

  (* Running a command *)

  (* -1, always: poc runs no other program on VMS (step 2's decision; a
     build writes a command procedure instead), so nothing is run. *)
  PROCEDURE System*(cmd: ARRAY OF CHAR): INTEGER;
  BEGIN
    RETURN -1
  END System;

  (* Files by name *)

  (* Deletes the file n: its highest version, when n names none. *)
  PROCEDURE Unlink*(VAR n: ARRAY OF CHAR): ErrorCode;
    VAR length, status: INTEGER;
  BEGIN
    IF ~Fill(n, length) THEN RETURN 2 END; (* an error status, of no facility *)
    status := POC_ERASE(given, length);
    IF ODD(status) THEN RETURN 0 END;
    RETURN status
  END Unlink;

  (* Directories *)

  (* The file name in the directory dir in path, cut short if path is too
     small: dir and name joined, with ":" between them when dir does not
     end with ":", "]" or ">" - a logical name standing for a directory -
     and nothing between them when it does, or when dir is "". *)
  PROCEDURE MakePath*(dir, name: ARRAY OF CHAR; VAR path: ARRAY OF CHAR);
    VAR i, j: LONGINT; last: CHAR;
  BEGIN
    i := 0;
    WHILE (i < LEN(dir)) & (dir[i] # 0X) & (i < LEN(path) - 1) DO path[i] := dir[i]; INC(i) END;
    IF (i > 0) & (i < LEN(path) - 1) THEN
      last := path[i - 1];
      IF (last # ":") & (last # "]") & (last # ">") THEN path[i] := ":"; INC(i) END
    END;
    j := 0;
    WHILE (j < LEN(name)) & (name[j] # 0X) & (i < LEN(path) - 1) DO path[i] := name[j]; INC(i); INC(j) END;
    IF LEN(path) > 0 THEN path[i] := 0X END
  END MakePath;

  (* Whether dir names a directory that exists: RMS parses it, which looks
     the directory up ($PARSE, with no file name). A dir that does not end
     with ":", "]" or ">" is taken as a logical name, with ":" after it. *)
  PROCEDURE IsDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR length: INTEGER;
  BEGIN
    RETURN Fill(dir, length) & AsDirectory(length) & ODD(POC_PARSE(given, length))
  END IsDirectory;

  (* Makes the directory dir and those it is in that are missing
     (LIB$CREATE_DIR); whether dir is a directory afterwards. dir is taken
     as IsDirectory takes it. *)
  PROCEDURE MakeDirectory*(dir: ARRAY OF CHAR): BOOLEAN;
    VAR length: INTEGER;
  BEGIN
    RETURN Fill(dir, length) & AsDirectory(length) & ODD(POC_CREATE_DIRECTORY(given, length))
  END MakeDirectory;

  (* Ending the process *)

  (* Ends the process as HALT(code) does, with code's low 8 bits, as on
     Unix: SS$_NORMAL for 0, otherwise an error status with code in it
     (%X10000000 + 8 * code + 2), which DCL does not print. *)
  PROCEDURE Exit*(code: LONGINT);
  BEGIN
    POC_HALT(SHORT(code MOD 256))
  END Exit;

  PROCEDURE InitProcessId;
  BEGIN
    PID := POC_PROCESS_ID();
    IF PID < 0 THEN PID := PID + MAX(INTEGER) + 1 END
  END InitProcessId;

  (* the default device, SYS$DISK, and the default directory *)
  PROCEDURE InitCWD;
    VAR count: INTEGER;
  BEGIN
    GetEnv("SYS$DISK", CWD);
    count := POC_DEFAULT_DIRECTORY(returned, nameLength - 1);
    Append(CWD, count)
  END InitCWD;

BEGIN
  InitProcessId;
  InitCWD;
  NL[0] := 0AX; NL[1] := 0X
END Platform.
