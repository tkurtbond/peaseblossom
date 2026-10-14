MODULE Platform;

  (* rtl/llvm/Platform.Mod's interface, voc's Platform, for VAX/VMS, over
     the services rtl/vax/PocRtl.mar calls: PLAN.md Phase 16 step 4 brought
     what poc's own source uses (GetEnv, Unlink, System, Exit, PID, CWD
     and NL; doc/developer/vax-macro32-backend.md, section 15, proposals 3,
     5, 7 and 8), Phase 17 step 3 the rest (section 19.1, proposals 1 to
     8). Directories, beside it, has the directories.

     A name is given to VMS as it is, so case does not matter in it, and a
     file name without a version means the highest one. RMS takes a file
     name of at most 255 characters, and $TRNLNM a logical name of at most
     255; a longer one names nothing here.

     A FILEHANDLE is an index into the table of open files below, 32 of
     them. StdIn, StdOut and StdErr are SYS$INPUT, SYS$OUTPUT and
     SYS$ERROR: StdIn is read a record at a time, an LF after each, and what
     is written to StdOut or StdErr goes through LineOutput, an LF ending a
     record, so that it comes out in order with Out's and Err's. When
     SYS$INPUT and SYS$OUTPUT are terminals, the text of an unfinished line
     of Out's is the prompt for StdIn's next record (Phase 17 step 3,
     section 19.11, proposal 2). A file
     opened by name is Files': New makes a new version, Stream_LF, and
     OldRO and OldRW open a Stream_LF, fixed-length or undefined file as
     its bytes, by block I/O, through one 512-byte block of it; OldRO reads
     a file of another record format a record at a time, an LF after each,
     as Files.Old does, counting its bytes when it opens it, and OldRW
     refuses one (RMS$_ORG).

     An ErrorCode is 0 for success, otherwise the VMS status of the service
     that failed, its low word under -O2 (where an INTEGER is a word),
     which is never 0 for a status RMS returns: its severity and message
     number are there. The error tests compare that part (POC_STATUS_CLASS).

     Time is local time, the only time VMS 5.5 keeps: GetTimeOfDay counts
     from 1 January 1970 local time, so it differs from Unix's count by the
     zone's offset.

     The routines of PocRtl.mar return a longword in R0, which a
     declaration here takes as an INTEGER: the whole longword under -OC,
     its low word under -O2. A length, at most 1024, fits either; a count
     that may not is passed by reference, as a LONGINT whose low longword
     the routine reads. *)

  IMPORT SYSTEM, LineOutput;

  CONST
    (* the handles of standard input, output and error *)
    StdIn* = 0;
    StdOut* = 1;
    StdErr* = 2;

    nameLength = 256; (* a name and its 0X *)
    controlSize = 768; (* PocRtl.mar's POC_F_SIZE, as Files' *)
    blockSize = 512;
    recordSize = 32767; (* the longest record RMS reads *)
    handles = 32;

    (* POC_FILE_OPEN_MODE's modes *)
    openReadOnly = 0;
    openReadWrite = 1;
    openNew = 2;
    openRecords = 3;

    (* POC_STATUS's statuses *)
    badHandle = 0;
    noHandleLeft = 1;
    notOpenedFor = 2;
    badArgument = 3;
    noSuchName = 4;

    (* POC_STATUS_CLASS's classes *)
    absentClass = 1;
    noDirectoryClass = 2;
    inaccessibleClass = 4;
    tooManyFilesClass = 8;
    otherDeviceClass = 16;
    timedOutClass = 32;

    (* 1 January 1970 as a VMS time: 100-nanosecond units since 17
       November 1858, 40587 days before *)
    unixEpoch = 35067168000000000;

  TYPE
    SignalHandler = PROCEDURE (signal: SYSTEM.INT32);

    (* 0, or the status of a service that failed; an open file's index in
       the table *)
    ErrorCode* = INTEGER;
    FileHandle* = LONGINT;

    (* which file a file is, and when it was last modified: the device's
       name as a counted string (16 bytes), the file ID (three words, then
       two zero bytes) and the revision date (a quadword), as
       POC_FILE_IDENTITY gives them *)
    FileIdentity* = RECORD
      bytes: ARRAY 32 OF CHAR
    END;

    Name = ARRAY nameLength OF CHAR;
    (* a file's FAB, RAB, NAM block, XABFHC and XABDAT, and its resultant
       name *)
    Control = ARRAY controlSize OF CHAR;
    Block = ARRAY blockSize OF SYSTEM.BYTE;
    (* POC_FILE_OPEN_MODE's: 1 to be read by block I/O, else 0; the
       end-of-file block; the first free byte in it *)
    Info = ARRAY 3 OF SYSTEM.INT32;
    (* $NUMTIM's and LIB$CVT_VECTIM's: year, month, day, hour, minute,
       second, hundredths *)
    TimeVector = ARRAY 7 OF SYSTEM.INT16;
    (* POC_PARSE_DIRECTORY's: the lengths of the device and the
       directory *)
    Parts = ARRAY 2 OF SYSTEM.INT32;

    (* an open file *)
    Entry = RECORD
      control: Control;
      block: Block; (* the block at blockStart, -1 for none *)
      inUse: BOOLEAN;
      writable: BOOLEAN; (* opened by OldRW or New *)
      byRecord: BOOLEAN; (* read a record at a time *)
      dirty: BOOLEAN; (* block has bytes not written out *)
      length, position, blockStart: LONGINT;
      (* a file read by record: its records' buffer, from POC_GET_MEMORY,
         and the current record's start and length, its LF included (0
         before the first) *)
      record: SYSTEM.ADDRESS;
      recordStart, recordLength: LONGINT
    END;

  VAR
    (* whether the machine stores the least significant byte first; the
       process's identification, reduced modulo 2^15 under -O2, as
       rtl/llvm's is when it does not fit an INTEGER; the default device and
       directory, at the start and after Chdir; the whence values for Seek;
       the line ending, LF, which a record's end stands for *)
    LittleEndian-: BOOLEAN;
    PID-: INTEGER;
    CWD-: ARRAY nameLength OF CHAR;
    SeekSet-, SeekCur-, SeekEnd-: INTEGER;
    NL-: ARRAY 3 OF CHAR;
    (* a name given to a service, and a value one gives back *)
    given, returned: Name;
    table: ARRAY handles OF Entry;
    (* whether SYS$INPUT and SYS$OUTPUT are terminals, when StdIn was
       opened: then Out's unfinished line is the prompt for its next
       record (design section 19.11, proposal 2) *)
    promptInput: BOOLEAN;
    (* the status of the last procedure here that failed, for Error *)
    lastError: ErrorCode;
    (* Time's zero, a VMS time *)
    timeStart: HUGEINT;
    (* the handlers set, kept for step 6 (design section 19.1, proposal 8) *)
    interruptHandler, quitHandler, badInstructionHandler: SignalHandler;

  PROCEDURE ["VMS"] POC_TRNLNM(VAR name: Name; length, index: INTEGER; VAR value: Name; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_ERASE(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_DEFAULT_DIRECTORY(VAR value: Name; size: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_PROCESS_ID(): INTEGER;
  PROCEDURE ["VMS"] POC_HALT(code: INTEGER);
  PROCEDURE ["VMS"] POC_FILE_OPEN_MODE(VAR control: Control; VAR name: Name; length, mode: SYSTEM.INT32;
                                       VAR info: Info): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_READ(VAR control: Control; VAR position: LONGINT; VAR block: Block): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_WRITE(VAR control: Control; VAR position: LONGINT; VAR block: Block;
                                   count: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_TRUNCATE(VAR control: Control; VAR position: LONGINT; VAR block: Block;
                                      count: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_GET(VAR control: Control; record: SYSTEM.ADDRESS; size: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_INPUT_GET(VAR control: Control; record: SYSTEM.ADDRESS; size: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_REWIND(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_FLUSH(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_CLOSE(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_IDENTITY(VAR control: Control; VAR identity: FileIdentity): INTEGER;
  PROCEDURE ["VMS"] POC_SET_REVISION(VAR name: Name; length: INTEGER; VAR time: HUGEINT): INTEGER;
  PROCEDURE ["VMS"] POC_GET_TIME(VAR time: HUGEINT): INTEGER;
  PROCEDURE ["VMS"] POC_NUMTIM(VAR time: HUGEINT; VAR vector: TimeVector): INTEGER;
  PROCEDURE ["VMS"] POC_VECTIM(VAR vector: TimeVector; VAR time: HUGEINT): INTEGER;
  PROCEDURE ["VMS"] POC_DELAY(VAR ms: LONGINT): INTEGER;
  PROCEDURE ["VMS"] POC_SPAWN(VAR command: Name; length: INTEGER; VAR status: LONGINT): INTEGER;
  PROCEDURE ["VMS"] POC_PARSE_DIRECTORY(VAR name: Name; length: INTEGER; VAR value: Name;
                                        VAR parts: Parts): INTEGER;
  PROCEDURE ["VMS"] POC_DEFINE_DISK(VAR device: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_SET_DIRECTORY(VAR directory: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_IS_TERMINAL(VAR name: Name; length: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_RENAME(VAR old: Name; oldLength: INTEGER; VAR new: Name; newLength: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_STATUS(which: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_STATUS_CLASS(status: INTEGER): INTEGER;
  PROCEDURE ["VMS"] POC_GET_MEMORY(bytes: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["VMS"] POC_FREE_MEMORY(address, bytes: SYSTEM.ADDRESS): INTEGER;

  (* s up to its 0X in given, and its length in length; FALSE if it is
     longer than a service takes, or has no 0X in its array and so names
     nothing (as rtl/llvm's) *)
  PROCEDURE Fill(s: ARRAY OF CHAR; VAR length: INTEGER): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO
      IF i = nameLength - 1 THEN RETURN FALSE END;
      given[i] := s[i]; INC(i)
    END;
    IF i = LEN(s) THEN RETURN FALSE END;
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

  (* count characters of returned from start appended to s, cut short if
     s cannot hold them *)
  PROCEDURE AppendPart(VAR s: ARRAY OF CHAR; start, count: LONGINT);
    VAR k: LONGINT;
  BEGIN
    FOR k := start TO start + count - 1 DO AppendChar(s, returned[k]) END
  END AppendPart;

  (* the first count characters of returned appended to s *)
  PROCEDURE Append(VAR s: ARRAY OF CHAR; count: INTEGER);
  BEGIN
    AppendPart(s, 0, count)
  END Append;

  (* e kept for Error, and returned; 0 when status is a success *)
  PROCEDURE Result(status: INTEGER): ErrorCode;
  BEGIN
    IF ODD(status) THEN RETURN 0 END;
    lastError := status;
    RETURN status
  END Result;

  (* POC_STATUS's status which, kept for Error *)
  PROCEDURE Failure(which: INTEGER): ErrorCode;
  BEGIN
    RETURN Result(POC_STATUS(which))
  END Failure;

  (* The status of a name s that Fill refused: RMS$_FNF if it has no 0X,
     as rtl/llvm's ENOENT, else SS$_BADPARAM *)
  PROCEDURE NameFailure(VAR s: ARRAY OF CHAR): ErrorCode;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(s)) & (s[i] # 0X) DO INC(i) END;
    IF i = LEN(s) THEN RETURN Failure(noSuchName) END;
    RETURN Failure(badArgument)
  END NameFailure;

  (* The status of the last procedure here that failed. *)
  PROCEDURE Error*(): ErrorCode;
  BEGIN
    RETURN lastError
  END Error;

  (* Error tests: whether the error code e means too many open files, no
     such directory, a rename to another device, no privilege, no such file
     or device, or a time-out (design section 19.1, proposal 3). Nothing
     here makes connections, and VMS restarts no service when an AST
     interrupts it, so ConnectionFailed and Interrupted are always FALSE. *)
  PROCEDURE InClass(e: ErrorCode; class: INTEGER): BOOLEAN;
  BEGIN
    RETURN (e # 0) & ODD(POC_STATUS_CLASS(e) DIV class)
  END InClass;

  PROCEDURE TooManyFiles*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN InClass(e, tooManyFilesClass)
  END TooManyFiles;

  PROCEDURE NoSuchDirectory*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN InClass(e, noDirectoryClass)
  END NoSuchDirectory;

  PROCEDURE DifferentFilesystems*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN InClass(e, otherDeviceClass)
  END DifferentFilesystems;

  PROCEDURE Inaccessible*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN InClass(e, inaccessibleClass)
  END Inaccessible;

  PROCEDURE Absent*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN InClass(e, absentClass)
  END Absent;

  PROCEDURE TimedOut*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN InClass(e, timedOutClass)
  END TimedOut;

  PROCEDURE ConnectionFailed*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN FALSE
  END ConnectionFailed;

  PROCEDURE Interrupted*(e: ErrorCode): BOOLEAN;
  BEGIN RETURN FALSE
  END Interrupted;

  (* File and path name length limits: ODS-2's file name, and RMS's whole
     specification (NAM$C_MAXRSS) *)
  PROCEDURE MaxNameLength*(): INTEGER;
  BEGIN RETURN 39
  END MaxNameLength;

  PROCEDURE MaxPathLength*(): INTEGER;
  BEGIN RETURN 255
  END MaxPathLength;

  (* Memory from the system, outside the collected heap: LIB$GET_VM and
     LIB$FREE_VM, the size kept in the 8 bytes before the block; 0 when
     there is none *)
  PROCEDURE OSAllocate*(size: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
    VAR block: SYSTEM.ADDRESS;
  BEGIN
    block := POC_GET_MEMORY(size + 8);
    IF block = 0 THEN RETURN 0 END;
    SYSTEM.PUT(block, size);
    RETURN block + 8
  END OSAllocate;

  PROCEDURE OSFree*(address: SYSTEM.ADDRESS);
    VAR size: SYSTEM.ADDRESS; status: INTEGER;
  BEGIN
    IF address # 0 THEN
      SYSTEM.GET(address - 8, size);
      status := POC_FREE_MEMORY(address - 8, size + 8)
    END
  END OSFree;

  (* The environment *)

  (* The logical name var translated, in val, cut short if val is too
     small for it; FALSE, and val unchanged, when there is no such name. It
     is looked up as a file name's is (LNM$FILE_DEV: the process's table,
     the job's, the group's, the system's), ignoring case. A search list's
     equivalence strings are joined with ",", Directories.pathSeparator. *)
  PROCEDURE getEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR): BOOLEAN;
    VAR length, index, count: INTEGER;
  BEGIN
    IF ~Fill(var, length) OR (length = 0) THEN RETURN FALSE END;
    index := 0;
    count := POC_TRNLNM(given, length, index, returned, nameLength - 1);
    IF count < 0 THEN RETURN FALSE END;
    IF LEN(val) > 0 THEN val[0] := 0X END;
    REPEAT
      IF index > 0 THEN AppendChar(val, ",") END;
      Append(val, count);
      INC(index);
      count := POC_TRNLNM(given, length, index, returned, nameLength - 1)
    UNTIL count < 0;
    RETURN TRUE
  END getEnv;

  (* The same, "" when there is no such name. *)
  PROCEDURE GetEnv*(var: ARRAY OF CHAR; VAR val: ARRAY OF CHAR);
  BEGIN
    IF ~getEnv(var, val) & (LEN(val) > 0) THEN val[0] := 0X END
  END GetEnv;

  (* Signals: on VMS Ctrl-C reaches a program as an AST and a bad
     instruction as a condition, which Phase 17 step 6 decides how to
     deliver; until then a handler set here is kept and never called
     (design section 19.1, proposal 8). *)
  PROCEDURE SetInterruptHandler*(handler: SignalHandler);
  BEGIN interruptHandler := handler
  END SetInterruptHandler;

  PROCEDURE SetQuitHandler*(handler: SignalHandler);
  BEGIN quitHandler := handler
  END SetQuitHandler;

  PROCEDURE SetBadInstructionHandler*(handler: SignalHandler);
  BEGIN badInstructionHandler := handler
  END SetBadInstructionHandler;

  (* Time *)

  (* x, which fits a LONGINT, as one: its low bytes *)
  PROCEDURE Low(x: HUGEINT): LONGINT;
    VAR result: LONGINT;
  BEGIN
    SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(result), SIZE(LONGINT));
    RETURN result
  END Low;

  (* x, which fits a word, as one: its low word *)
  PROCEDURE Word(x: LONGINT): SYSTEM.INT16;
    VAR result: SYSTEM.INT16;
  BEGIN
    SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(result), 2);
    RETURN result
  END Word;

  (* The system time now, a VMS time *)
  PROCEDURE Now(): HUGEINT;
    VAR time: HUGEINT; status: INTEGER;
  BEGIN
    time := 0; status := POC_GET_TIME(time);
    RETURN time
  END Now;

  (* time in the Oberon system's format: d holds the year modulo 100 (bits
     9 and up), the month 1..12 (bits 5-8) and the day (bits 0-4); t the
     hour (bits 12 and up), the minute (bits 6-11) and the second (bits
     0-5) *)
  PROCEDURE Clock(time: HUGEINT; VAR t, d: LONGINT);
    VAR vector: TimeVector; status: INTEGER; year, month, day, hour, minute, second: LONGINT;
  BEGIN
    status := POC_NUMTIM(time, vector);
    year := vector[0]; month := vector[1]; day := vector[2];
    hour := vector[3]; minute := vector[4]; second := vector[5];
    d := year MOD 100 * 512 + month * 32 + day;
    t := hour * 4096 + minute * 64 + second
  END Clock;

  (* The local time now, in the Oberon system's format (Clock, above). *)
  PROCEDURE GetClock*(VAR t, d: LONGINT);
  BEGIN
    Clock(Now(), t, d)
  END GetClock;

  (* The time now, in seconds and microseconds since 1 January 1970 local
     time (the seconds wrap in 2038 under -O2, where a LONGINT has 32 bits,
     as voc's). *)
  PROCEDURE GetTimeOfDay*(VAR sec, usec: LONGINT);
    VAR since: HUGEINT;
  BEGIN
    since := Now() - unixEpoch;
    sec := Low(since DIV 10000000); usec := Low(since MOD 10000000 DIV 10)
  END GetTimeOfDay;

  (* The milliseconds since the program started, modulo 7FFFFFFFH. *)
  PROCEDURE Time*(): LONGINT;
  BEGIN
    RETURN Low((Now() - timeStart) DIV 10000 MOD 7FFFFFFFH)
  END Time;

  (* Sleeps for ms milliseconds. *)
  PROCEDURE Delay*(ms: LONGINT);
    VAR status: INTEGER;
  BEGIN
    status := POC_DELAY(ms)
  END Delay;

  (* Running a command *)

  (* Runs the DCL command cmd in a subprocess (LIB$SPAWN) and waits for
     it: 0 when its completion status is a success, otherwise that status,
     its low word under -O2, never 0; -1 when no subprocess could be made,
     or cmd is too long (design section 19.1, proposal 6). *)
  PROCEDURE System*(cmd: ARRAY OF CHAR): INTEGER;
    VAR length: INTEGER; status: LONGINT;
  BEGIN
    IF ~Fill(cmd, length) THEN RETURN -1 END;
    status := 0;
    IF ~ODD(POC_SPAWN(given, length, status)) THEN RETURN -1 END;
    IF ODD(status) THEN RETURN 0 END;
    IF MAX(INTEGER) = 32767 THEN
      status := status MOD 65536;
      IF status > 32767 THEN DEC(status, 65536) END
    END;
    RETURN SHORT(status)
  END System;

  (* Files by handle *)

  (* whether h is the handle of an open file *)
  PROCEDURE EntryOf(h: FileHandle): BOOLEAN;
  BEGIN
    RETURN (h >= 0) & (h < handles) & table[h].inUse
  END EntryOf;

  (* The next record of the file read by record at k into its buffer, its
     length with its LF in recordLength, after the one before; FALSE at the
     end of the file, status 0 then, or when it cannot be read *)
  PROCEDURE NextRecord(k: LONGINT; VAR status: INTEGER): BOOLEAN;
    VAR n: INTEGER;
  BEGIN
    status := 0;
    IF (k = StdIn) & promptInput THEN n := POC_INPUT_GET(table[k].control, table[k].record, recordSize)
    ELSE n := POC_FILE_GET(table[k].control, table[k].record, recordSize)
    END;
    IF n = -1 THEN RETURN FALSE END;
    IF n < 0 THEN status := POC_STATUS(badArgument); RETURN FALSE END;
    INC(table[k].recordStart, table[k].recordLength);
    table[k].recordLength := LONG(n) + 1;
    RETURN TRUE
  END NextRecord;

  (* The file read by record at k read from its first record again *)
  PROCEDURE Rewind(k: LONGINT): INTEGER;
    VAR status: INTEGER;
  BEGIN
    status := POC_FILE_REWIND(table[k].control);
    IF ~ODD(status) THEN RETURN status END;
    table[k].recordStart := 0; table[k].recordLength := 0;
    RETURN 0
  END Rewind;

  (* The records of the file read by record at k counted, LFs included,
     its length then that, and the file wound back to its start; 0, or the
     status of a failure. Not for StdIn, which is not counted. *)
  PROCEDURE CountRecords(k: LONGINT): INTEGER;
    VAR status: INTEGER;
  BEGIN
    WHILE NextRecord(k, status) DO END;
    IF status # 0 THEN RETURN status END;
    table[k].length := table[k].recordStart + table[k].recordLength;
    RETURN Rewind(k)
  END CountRecords;

  (* The entry k given up: its record buffer freed, the file closed *)
  PROCEDURE Release(k: LONGINT);
    VAR status: INTEGER;
  BEGIN
    IF table[k].record # 0 THEN
      status := POC_FREE_MEMORY(table[k].record, recordSize); table[k].record := 0
    END;
    status := POC_FILE_CLOSE(table[k].control);
    table[k].inUse := FALSE
  END Release;

  (* The file name opened in mode in a free entry, h its handle. *)
  PROCEDURE Open(VAR n: ARRAY OF CHAR; mode: INTEGER; VAR h: FileHandle): ErrorCode;
    VAR length, status: INTEGER; info: Info; k, block: LONGINT;
  BEGIN
    IF ~Fill(n, length) THEN RETURN NameFailure(n)
    ELSIF length = 0 THEN RETURN Failure(badArgument)
    END;
    k := StdErr + 1;
    WHILE (k < handles) & table[k].inUse DO INC(k) END;
    IF k = handles THEN RETURN Failure(noHandleLeft) END;
    status := POC_FILE_OPEN_MODE(table[k].control, given, length, mode, info);
    IF ~ODD(status) THEN RETURN Result(status) END;
    table[k].inUse := TRUE;
    table[k].writable := (mode = openReadWrite) OR (mode = openNew);
    table[k].byRecord := info[0] = 0;
    table[k].dirty := FALSE;
    table[k].position := 0; table[k].blockStart := -1;
    table[k].record := 0; table[k].recordStart := 0; table[k].recordLength := 0;
    IF table[k].byRecord THEN
      table[k].record := POC_GET_MEMORY(recordSize);
      IF table[k].record = 0 THEN
        status := POC_FILE_CLOSE(table[k].control); table[k].inUse := FALSE;
        RETURN Failure(noHandleLeft)
      END;
      status := CountRecords(k);
      IF status # 0 THEN
        Release(k); RETURN Result(status)
      END
    ELSE
      block := info[1]; table[k].length := 0;
      IF block > 0 THEN table[k].length := (block - 1) * blockSize + info[2] END
    END;
    h := k;
    RETURN 0
  END Open;

  (* Opens the file n to read. *)
  PROCEDURE OldRO*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
  BEGIN RETURN Open(n, openReadOnly, h)
  END OldRO;

  (* Opens the file n to read and write. *)
  PROCEDURE OldRW*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
  BEGIN RETURN Open(n, openReadWrite, h)
  END OldRW;

  (* Creates a new version of the file n, to read and write. *)
  PROCEDURE New*(VAR n: ARRAY OF CHAR; VAR h: FileHandle): ErrorCode;
  BEGIN RETURN Open(n, openNew, h)
  END New;

  (* StdIn's entry, SYS$INPUT opened the first time it is read *)
  PROCEDURE OpenInput(): ErrorCode;
    VAR length, status: INTEGER; info: Info;
  BEGIN
    IF table[StdIn].inUse THEN RETURN 0 END;
    promptInput := Fill("SYS$INPUT", length) & (POC_IS_TERMINAL(given, length) = 1)
      & Fill("SYS$OUTPUT", length) & (POC_IS_TERMINAL(given, length) = 1);
    IF ~Fill("SYS$INPUT", length) THEN RETURN Failure(badArgument) END;
    status := POC_FILE_OPEN_MODE(table[StdIn].control, given, length, openRecords, info);
    IF ~ODD(status) THEN RETURN Result(status) END;
    table[StdIn].record := POC_GET_MEMORY(recordSize);
    IF table[StdIn].record = 0 THEN
      status := POC_FILE_CLOSE(table[StdIn].control);
      RETURN Failure(noHandleLeft)
    END;
    table[StdIn].inUse := TRUE; table[StdIn].byRecord := TRUE;
    table[StdIn].writable := FALSE; table[StdIn].dirty := FALSE;
    table[StdIn].position := 0; table[StdIn].blockStart := -1;
    table[StdIn].recordStart := 0; table[StdIn].recordLength := 0;
    table[StdIn].length := MAX(LONGINT);
    RETURN 0
  END OpenInput;

  (* The block of the file at k written out, if it has changes: as many
     of its bytes as the file has, so that RMS keeps its end there *)
  PROCEDURE WriteBlock(k: LONGINT): INTEGER;
    VAR count: LONGINT; status: INTEGER;
  BEGIN
    IF ~table[k].dirty THEN RETURN 0 END;
    count := table[k].length - table[k].blockStart;
    IF count > blockSize THEN count := blockSize END;
    status := POC_FILE_WRITE(table[k].control, table[k].blockStart, table[k].block, SHORT(count));
    IF ~ODD(status) THEN RETURN status END;
    table[k].dirty := FALSE;
    RETURN 0
  END WriteBlock;

  (* The block of the file at k that holds the byte at position in its
     buffer, the one there written out first; a block past the file's
     end, which RMS does not have, is zeros *)
  PROCEDURE LoadBlock(k, position: LONGINT): INTEGER;
    VAR start: LONGINT; status, i: INTEGER;
  BEGIN
    start := position DIV blockSize * blockSize;
    IF table[k].blockStart = start THEN RETURN 0 END;
    status := WriteBlock(k);
    IF status # 0 THEN RETURN status END;
    table[k].blockStart := -1;
    IF start < table[k].length THEN
      status := POC_FILE_READ(table[k].control, start, table[k].block);
      IF ~ODD(status) THEN RETURN status END
    ELSE
      FOR i := 0 TO blockSize - 1 DO table[k].block[i] := 0X END
    END;
    table[k].blockStart := start;
    RETURN 0
  END LoadBlock;

  (* Whether h is a terminal: StdIn, StdOut and StdErr asked of their
     devices; a file opened by name is not (design section 19.1, proposal
     8). *)
  PROCEDURE IsConsole*(h: FileHandle): BOOLEAN;
    VAR length: INTEGER; ok: BOOLEAN;
  BEGIN
    IF h = StdIn THEN ok := Fill("SYS$INPUT", length)
    ELSIF h = StdOut THEN ok := Fill("SYS$OUTPUT", length)
    ELSIF h = StdErr THEN ok := Fill("SYS$ERROR", length)
    ELSE ok := FALSE
    END;
    RETURN ok & (POC_IS_TERMINAL(given, length) = 1)
  END IsConsole;

  (* Reads at most l bytes from the file read by record at k to the
     address p; n is how many it read, 0 at the end of the file. *)
  PROCEDURE ReadRecords(k: LONGINT; p: SYSTEM.ADDRESS; l: LONGINT; VAR n: LONGINT): ErrorCode;
    VAR offset, count: LONGINT; status: INTEGER;
  BEGIN
    n := 0;
    WHILE n < l DO
      IF table[k].position >= table[k].recordStart + table[k].recordLength THEN
        IF ~NextRecord(k, status) THEN RETURN Result(status) END
      ELSE
        offset := table[k].position - table[k].recordStart;
        IF offset = table[k].recordLength - 1 THEN
          SYSTEM.PUT(p + n, 0AX); count := 1
        ELSE
          count := table[k].recordLength - 1 - offset;
          IF count > l - n THEN count := l - n END;
          SYSTEM.MOVE(table[k].record + offset, p + n, count)
        END;
        INC(n, count); INC(table[k].position, count)
      END
    END;
    RETURN 0
  END ReadRecords;

  (* Reads at most l bytes from h to the address p; n is how many it read,
     0 at the end of the file. *)
  PROCEDURE Read*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT; VAR n: LONGINT): ErrorCode;
    VAR k, offset, count: LONGINT; status: INTEGER;
  BEGIN
    n := 0;
    IF h = StdIn THEN
      status := OpenInput();
      IF status # 0 THEN RETURN status END
    END;
    IF ~EntryOf(h) THEN RETURN Failure(badHandle) END;
    k := h;
    IF table[k].byRecord THEN RETURN ReadRecords(k, p, l, n) END;
    WHILE (n < l) & (table[k].position < table[k].length) DO
      status := LoadBlock(k, table[k].position);
      IF status # 0 THEN RETURN Result(status) END;
      offset := table[k].position - table[k].blockStart;
      count := blockSize - offset;
      IF count > l - n THEN count := l - n END;
      IF count > table[k].length - table[k].position THEN count := table[k].length - table[k].position END;
      SYSTEM.MOVE(SYSTEM.ADR(table[k].block[offset]), p + n, count);
      INC(n, count); INC(table[k].position, count)
    END;
    RETURN 0
  END Read;

  (* Reads at most LEN(b) bytes from h into b; n is how many it read. *)
  PROCEDURE ReadBuf*(h: FileHandle; VAR b: ARRAY OF SYSTEM.BYTE; VAR n: LONGINT): ErrorCode;
  BEGIN RETURN Read(h, SYSTEM.ADR(b), LEN(b), n)
  END ReadBuf;

  (* The l bytes at the address p written to the file at k at its
     position, or zeros if p is 0 *)
  PROCEDURE WriteBytes(k: LONGINT; p: SYSTEM.ADDRESS; l: LONGINT): INTEGER;
    VAR n, offset, count, i: LONGINT; status: INTEGER;
  BEGIN
    n := 0;
    WHILE n < l DO
      status := LoadBlock(k, table[k].position);
      IF status # 0 THEN RETURN status END;
      offset := table[k].position - table[k].blockStart;
      count := blockSize - offset;
      IF count > l - n THEN count := l - n END;
      IF p = 0 THEN
        FOR i := offset TO offset + count - 1 DO table[k].block[i] := 0X END
      ELSE
        SYSTEM.MOVE(p + n, SYSTEM.ADR(table[k].block[offset]), count)
      END;
      table[k].dirty := TRUE;
      INC(n, count); INC(table[k].position, count);
      IF table[k].position > table[k].length THEN table[k].length := table[k].position END
    END;
    RETURN 0
  END WriteBytes;

  (* The bytes from the file's end to position made zeros, the file at k
     extended to it; its position then where it was *)
  PROCEDURE Extend(k, position: LONGINT): INTEGER;
    VAR at: LONGINT; status: INTEGER;
  BEGIN
    IF position <= table[k].length THEN RETURN 0 END;
    at := table[k].position;
    table[k].position := table[k].length;
    status := WriteBytes(k, 0, position - table[k].length);
    table[k].position := at;
    RETURN status
  END Extend;

  (* Writes the l bytes at the address p to h, StdOut and StdErr through
     LineOutput, each LF ending a record. *)
  PROCEDURE Write*(h: FileHandle; p: SYSTEM.ADDRESS; l: LONGINT): ErrorCode;
    VAR k, i: LONGINT; ch: CHAR; stream, status: INTEGER;
  BEGIN
    IF (h = StdOut) OR (h = StdErr) THEN
      IF h = StdOut THEN stream := LineOutput.output ELSE stream := LineOutput.error END;
      FOR i := 0 TO l - 1 DO
        SYSTEM.GET(p + i, ch);
        IF ch = 0AX THEN LineOutput.Ln(stream) ELSE LineOutput.Char(stream, ch) END
      END;
      RETURN 0
    END;
    IF ~EntryOf(h) THEN RETURN Failure(badHandle) END;
    k := h;
    IF ~table[k].writable THEN RETURN Failure(notOpenedFor) END;
    status := Extend(k, table[k].position);
    IF status = 0 THEN status := WriteBytes(k, p, l) END;
    RETURN Result(status)
  END Write;

  (* Writes out what is kept of h, and what RMS holds of it ($FLUSH). *)
  PROCEDURE Sync*(h: FileHandle): ErrorCode;
    VAR k: LONGINT; status: INTEGER;
  BEGIN
    IF (h = StdOut) OR (h = StdErr) THEN RETURN 0 END;
    IF ~EntryOf(h) THEN RETURN Failure(badHandle) END;
    k := h;
    IF ~table[k].writable THEN RETURN 0 END;
    status := WriteBlock(k);
    IF status = 0 THEN status := POC_FILE_FLUSH(table[k].control) END;
    RETURN Result(status)
  END Sync;

  (* Closes h. *)
  PROCEDURE Close*(h: FileHandle): ErrorCode;
    VAR k: LONGINT; status: INTEGER;
  BEGIN
    IF (h = StdOut) OR (h = StdErr) THEN RETURN 0 END;
    IF ~EntryOf(h) THEN RETURN Failure(badHandle) END;
    k := h;
    status := WriteBlock(k);
    Release(k);
    RETURN Result(status)
  END Close;

  (* Moves h's position to offset from whence: SeekSet (the start),
     SeekCur (the position) or SeekEnd (the end). A file read by record is
     read from its first record again to go back; StdIn cannot go back. *)
  PROCEDURE Seek*(h: FileHandle; offset: LONGINT; whence: INTEGER): ErrorCode;
    VAR k, target: LONGINT; status: INTEGER;
  BEGIN
    IF ~EntryOf(h) OR (h = StdIn) THEN RETURN Failure(badHandle) END;
    k := h;
    IF whence = SeekSet THEN target := offset
    ELSIF whence = SeekCur THEN target := table[k].position + offset
    ELSIF whence = SeekEnd THEN target := table[k].length + offset
    ELSE RETURN Failure(badArgument)
    END;
    IF target < 0 THEN RETURN Failure(badArgument) END;
    IF table[k].byRecord & (target < table[k].recordStart) THEN
      status := Rewind(k);
      IF status # 0 THEN RETURN Result(status) END
    END;
    table[k].position := target;
    RETURN 0
  END Seek;

  (* Cuts h, or extends it with zeros, to l bytes: a shorter file ends
     after the block that holds its new end is written with
     truncate-on-put. *)
  PROCEDURE Truncate*(h: FileHandle; l: LONGINT): ErrorCode;
    VAR k, start: LONGINT; status: INTEGER;
  BEGIN
    IF ~EntryOf(h) THEN RETURN Failure(badHandle) END;
    k := h;
    IF ~table[k].writable THEN RETURN Failure(notOpenedFor) END;
    IF l < 0 THEN RETURN Failure(badArgument) END;
    IF l >= table[k].length THEN RETURN Result(Extend(k, l)) END;
    status := LoadBlock(k, l);
    IF status # 0 THEN RETURN Result(status) END;
    start := table[k].blockStart;
    status := POC_FILE_TRUNCATE(table[k].control, start, table[k].block, SHORT(l - start));
    IF ~ODD(status) THEN RETURN Result(status) END;
    table[k].dirty := FALSE; table[k].length := l;
    RETURN 0
  END Truncate;

  (* The length of h in l. *)
  PROCEDURE Size*(h: FileHandle; VAR l: LONGINT): ErrorCode;
  BEGIN
    IF ~EntryOf(h) OR (h = StdIn) THEN RETURN Failure(badHandle) END;
    l := table[h].length;
    RETURN 0
  END Size;

  (* File identities: which file it is, and when it was last modified *)

  (* The identity of the open file h, or of the file named n *)
  PROCEDURE Identify*(h: FileHandle; VAR identity: FileIdentity): ErrorCode;
  BEGIN
    IF ~EntryOf(h) OR (h = StdIn) THEN RETURN Failure(badHandle) END;
    RETURN Result(POC_FILE_IDENTITY(table[h].control, identity))
  END Identify;

  PROCEDURE IdentifyByName*(n: ARRAY OF CHAR; VAR identity: FileIdentity): ErrorCode;
    VAR h: FileHandle; e: ErrorCode;
  BEGIN
    e := OldRO(n, h);
    IF e # 0 THEN RETURN e END;
    e := Identify(h, identity);
    Release(h);
    RETURN e
  END IdentifyByName;

  (* Whether i1 and i2 are the same file (device and file ID); whether
     they were last modified at the same time (the revision date); target's
     time made source's (in the identity, not the file) *)
  PROCEDURE SameFile*(i1, i2: FileIdentity): BOOLEAN;
    VAR k: INTEGER;
  BEGIN
    k := 0;
    WHILE (k < 24) & (i1.bytes[k] = i2.bytes[k]) DO INC(k) END;
    RETURN k = 24
  END SameFile;

  PROCEDURE SameFileTime*(i1, i2: FileIdentity): BOOLEAN;
    VAR k: INTEGER;
  BEGIN
    k := 24;
    WHILE (k < 32) & (i1.bytes[k] = i2.bytes[k]) DO INC(k) END;
    RETURN k = 32
  END SameFileTime;

  PROCEDURE SetMTime*(VAR target: FileIdentity; source: FileIdentity);
    VAR k: INTEGER;
  BEGIN
    FOR k := 24 TO 31 DO target.bytes[k] := source.bytes[k] END
  END SetMTime;

  (* i's modification time, in local time in GetClock's format. *)
  PROCEDURE MTimeAsClock*(i: FileIdentity; VAR t, d: LONGINT);
    VAR time: HUGEINT;
  BEGIN
    SYSTEM.MOVE(SYSTEM.ADR(i.bytes[24]), SYSTEM.ADR(time), 8);
    Clock(time, t, d)
  END MTimeAsClock;

  (* Sets the file n's revision date to the local time given, month
     1..12: the file is opened to be written and closed with it. *)
  PROCEDURE SetFileMTime*(VAR n: ARRAY OF CHAR; year, month, day, hour, minute, second: LONGINT): ErrorCode;
    VAR length, status: INTEGER; vector: TimeVector; time: HUGEINT;
  BEGIN
    IF ~Fill(n, length) THEN RETURN NameFailure(n)
    ELSIF length = 0 THEN RETURN Failure(badArgument)
    END;
    vector[0] := Word(year); vector[1] := Word(month); vector[2] := Word(day);
    vector[3] := Word(hour); vector[4] := Word(minute); vector[5] := Word(second);
    vector[6] := 0;
    time := 0;
    status := POC_VECTIM(vector, time);
    IF ~ODD(status) THEN RETURN Result(status) END;
    RETURN Result(POC_SET_REVISION(given, length, time))
  END SetFileMTime;

  (* Files by name *)

  (* Deletes the file n: its highest version, when n names none. *)
  PROCEDURE Unlink*(VAR n: ARRAY OF CHAR): ErrorCode;
    VAR length: INTEGER;
  BEGIN
    IF ~Fill(n, length) THEN RETURN NameFailure(n) END;
    RETURN Result(POC_ERASE(given, length))
  END Unlink;

  (* Renames the file o to n, a new version if there is a file n
     ($RENAME). *)
  PROCEDURE Rename*(VAR o, n: ARRAY OF CHAR): ErrorCode;
    VAR oldName: Name; oldLength, length: INTEGER;
  BEGIN
    IF ~Fill(o, oldLength) THEN RETURN NameFailure(o) END;
    oldName := given;
    IF ~Fill(n, length) THEN RETURN NameFailure(n) END;
    RETURN Result(POC_RENAME(oldName, oldLength, given, length))
  END Rename;

  (* The default directory *)

  (* Makes the directory n, as VMS writes one ("[.SUB]", "DUA1:[USERS]",
     "SYS$LOGIN"), the default: its device SYS$DISK, defined in user mode,
     and its directory the default, put back when the program ends (design
     section 19.1, proposal 7); CWD then names it. A name with a file name
     or type in it is not a directory (RMS$_DIR). *)
  PROCEDURE Chdir*(VAR n: ARRAY OF CHAR): ErrorCode;
    VAR length, status: INTEGER; parts: Parts; device, directory: Name;
  BEGIN
    IF ~Fill(n, length) THEN RETURN NameFailure(n)
    ELSIF length = 0 THEN RETURN Failure(badArgument)
    END;
    status := POC_PARSE_DIRECTORY(given, length, returned, parts);
    IF ~ODD(status) THEN RETURN Result(status) END;
    device := ""; AppendPart(device, 0, parts[0]);
    directory := ""; AppendPart(directory, parts[0], parts[1]);
    status := POC_DEFINE_DISK(device, SHORT(parts[0]));
    IF ~ODD(status) THEN RETURN Result(status) END;
    status := POC_SET_DIRECTORY(directory, SHORT(parts[1]));
    IF ~ODD(status) THEN RETURN Result(status) END;
    COPY(device, CWD); AppendPart(CWD, parts[0], parts[1]);
    RETURN 0
  END Chdir;

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
  LittleEndian := TRUE;
  timeStart := Now();
  InitProcessId;
  InitCWD;
  SeekSet := 0; SeekCur := 1; SeekEnd := 2;
  NL[0] := 0AX; NL[1] := 0X
END Platform.
