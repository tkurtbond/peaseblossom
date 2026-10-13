MODULE Files;

  (* PLAN.md Phase 16 step 4 and Phase 17 step 3 (doc/developer/vax-
     macro32-backend.md, section 15, proposal 2, and section 19.3):
     rtl/llvm/Files.Mod's interface, which is voc's, for VAX/VMS, over RMS
     through the routines in rtl/vax/PocRtl.mar and over Platform. Each
     procedure behaves as rtl/llvm's does, except where this says
     otherwise.

     THE MODEL is rtl/llvm's: a File is a byte sequence with a length, a
     Rider a position in one and the result of the last operation.

     A FILE FILES MAKES is Stream_LF, with carriage return carriage
     control, written and read by block I/O ($WRITE, $READ), so that every
     byte comes back as it was written and MACRO, LINK and TYPE read it as
     text. A File keeps one 512-byte block of it; RMS keeps the file's end
     at the highest byte written.

     NEW AND REGISTER. New makes nothing on disk. Its name is expanded
     against the default directory when it is given ($PARSE). The first
     block written out (or Close, or Register) creates the file under a
     name of its own, POC_<process>_<n>.TMP, in that directory, and
     Register renames it that name, as a new version: a compiler that stops
     half way leaves the files it had, and a program that changes directory
     in between still registers where it meant to.

     OLD AND WRITING. Old opens a file to be read, and the first write
     (Write, WriteBytes, a typed write, Purge) opens it again to be read
     and written: RMS sets a file's revision date when it is closed after
     being opened to be written, written to or not (RMS Reference, chapter
     15), and a file read should keep its date. Both share the file with
     others reading and writing it, so two Old calls for one file give two
     independent Files. A File stays usable after Close and Register: the
     next operation opens it again.

     A FILE OLD OPENS of another record format - variable-length or VFC,
     as FTP in ASCII mode and the editors write, Stream or Stream_CR - is
     read a record at a time ($GET), an LF (0AX) after each, so that a
     source written on VMS reads as it does on Unix. Old reads it through
     once to count its bytes, LFs included, for Length. A Stream_LF,
     fixed-length or undefined file is read as its bytes, its length from
     the end-of-file block and the first free byte in it. Writing to one of
     another format is an error, since bytes written would break its
     records.

     OLD AND THE SEARCH PATH. A name with ":", "[" or "<" in it is looked
     for where it says. Any other is looked for in each directory of the
     search path in turn, which is just the default directory until
     SetSearchPath sets one: directories separated by ",", as in
     POC$IMPORT, blanks around them ignored. Each is a directory ([.SUB],
     DUA1:[X.Y]) or a logical name, which gets a ":" after it; a leading
     "~" stands for SYS$LOGIN, and "~[.LIB]" is the directory LIB in it.

     THE TYPED RIDERS write Oakwood's external format, as rtl/llvm's, the
     same bytes on every system: a REAL is converted from F_floating to
     IEEE single and back, a LONGREAL from G_floating to IEEE double.
     Where the ranges differ: a VAX value too small for IEEE's normal
     range is written as an IEEE denormal, rounded to nearest, ties to
     even; an IEEE denormal reads as 0 (the VAX has no denormals and no
     -0), an IEEE value too large for the VAX or an infinity as the
     largest VAX value of its sign, and a NaN as the reserved operand,
     which faults when it is computed with.

     FINALIZATION. Every File is registered with the collector
     (GarbageCollectedHeap.RegisterFinalizer), as rtl/llvm's are: when one
     is no longer reachable, or the program ends, its block is written out
     and it is closed, and the temporary file of a New file never
     registered is deleted.

     A name is given to RMS as it is: case does not matter, and a missing
     version means the highest. Delete deletes the highest version, and
     Rename, like Register, makes a new version, so that an existing file
     of the new name stays, as an older version. An error that cannot be
     reported to the caller - a file that cannot be created or written -
     stops the program with a message and HALT(99), as rtl/llvm's does. *)

  IMPORT SYSTEM, Platform, GarbageCollectedHeap;

  CONST
    blockSize = 512;
    nameLength = 256; (* a name and its 0X, as RMS takes at most 255 *)
    controlSize = 768; (* PocRtl.mar's POC_F_SIZE, which it checks *)
    recordSize = 32767; (* the longest record RMS reads *)

  TYPE
    Name = ARRAY nameLength OF CHAR;
    (* the file's FAB, RAB, NAM block, XABFHC and XABDAT, and its resultant name *)
    Control = ARRAY controlSize OF CHAR;
    Block = ARRAY blockSize OF SYSTEM.BYTE;
    Record = ARRAY recordSize OF CHAR;
    (* POC_FILE_OPEN's: 1 to be read by block I/O, else 0; the end-of-file
       block; the first free byte in it *)
    Info = ARRAY 3 OF SYSTEM.INT32;
    File* = POINTER TO FileDesc;
    FileDesc = RECORD
      control: Control;
      block: Block; (* the block at blockStart, -1 for none *)
      name: Name; (* as given to Old or New *)
      registerName: Name; (* a New file's name, expanded *)
      isNew: BOOLEAN; (* from New and not registered yet *)
      created: BOOLEAN; (* the file is on disk *)
      open: BOOLEAN; (* the control's file is open *)
      writable: BOOLEAN; (* and open to be written *)
      dirty: BOOLEAN; (* block has bytes not written out *)
      byRecord: BOOLEAN; (* read a record at a time *)
      length, onDisk, blockStart: LONGINT;
      (* a file read by record: the current record, its start in the file
         and its length with its LF (0 before the first) *)
      record: POINTER TO Record;
      recordStart, recordLength: LONGINT
    END;
    (* a position in a file to read or write at, with the result of the
       last operation *)
    Rider* = RECORD
      res*: LONGINT; (* 0 after a successful operation *)
      eof*: BOOLEAN; (* set when a read went past the end *)
      file: File;
      position: LONGINT
    END;

  VAR
    (* the longest path and file name the system takes (Platform's) *)
    MaxPathLength-, MaxNameLength-: INTEGER;
    searchPath: POINTER TO ARRAY OF CHAR; (* NIL: the default directory *)
    home: Name; (* SYS$LOGIN *)

  PROCEDURE ["VMS"] POC_FILE_OPEN(VAR control: Control; VAR name: Name; length: SYSTEM.INT32;
                                  VAR info: Info): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_REOPEN(VAR control: Control; VAR info: Info; write: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_CREATE(VAR control: Control; VAR name: Name; length: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_READ(VAR control: Control; VAR position: LONGINT; VAR block: Block): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_WRITE(VAR control: Control; VAR position: LONGINT; VAR block: Block;
                                   count: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_TRUNCATE(VAR control: Control; VAR position: LONGINT; VAR block: Block;
                                      count: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_GET(VAR control: Control; VAR record: Record; size: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_REWIND(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_CLOSE(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_RENAME(VAR control: Control; VAR name: Name; length: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_IDENTITY(VAR control: Control; VAR identity: Platform.FileIdentity): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_NAME(VAR control: Control; VAR value: Name; size: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_EXPAND_NAME(VAR name: Name; length: SYSTEM.INT32; VAR value: Name;
                                    size: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_FAIL(VAR message: Name; messageLength: SYSTEM.INT32;
                                  VAR name: Name; nameLength: SYSTEM.INT32);
  PROCEDURE ["VMS"] POC_ERASE(VAR name: Name; length: SYSTEM.INT32): INTEGER;

  (* the length of s up to its 0X *)
  PROCEDURE Length0X(VAR s: ARRAY OF CHAR): INTEGER;
    VAR n: INTEGER;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END Length0X;

  (* An error nothing above can be told about: says what and of which file,
     on SYS$ERROR, and stops the program. *)
  PROCEDURE Fail(message: ARRAY OF CHAR; f: File);
    VAR text, name: Name; n: INTEGER;
  BEGIN
    COPY(message, text);
    IF f # NIL THEN COPY(f.name, name); n := Length0X(name) ELSE n := 0 END;
    POC_FILE_FAIL(text, Length0X(text), name, n)
  END Fail;

  (* name in s, and its length in n; FALSE if it is "" or too long *)
  PROCEDURE CopyName(VAR name: ARRAY OF CHAR; VAR s: Name; VAR n: INTEGER): BOOLEAN;
  BEGIN
    n := Length0X(name);
    IF (n = 0) OR (n >= nameLength) THEN RETURN FALSE END;
    COPY(name, s);
    RETURN TRUE
  END CopyName;

  (* A New file's file made on disk, if it is not yet. *)
  PROCEDURE Create(f: File);
  BEGIN
    IF ~f.created THEN
      IF ~ODD(POC_FILE_CREATE(f.control, f.registerName, Length0X(f.registerName))) THEN
        Fail("file not created", f)
      END;
      f.created := TRUE; f.open := TRUE; f.writable := TRUE
    END
  END Create;

  (* The control's file open again, to be read, after Close. *)
  PROCEDURE Open(f: File);
    VAR info: Info;
  BEGIN
    IF ~f.open THEN
      IF ~ODD(POC_FILE_REOPEN(f.control, info, 0)) THEN Fail("file not reopened", f) END;
      f.open := TRUE
    END
  END Open;

  (* f open to be written (OLD AND WRITING above): a New file made, any
     other opened again to be read and written. *)
  PROCEDURE MakeWritable(f: File);
    VAR info: Info;
  BEGIN
    IF ~f.created THEN Create(f)
    ELSIF ~f.writable THEN
      IF f.open THEN
        IF ~ODD(POC_FILE_CLOSE(f.control)) THEN Fail("error reading file", f) END;
        f.open := FALSE
      END;
      IF ~ODD(POC_FILE_REOPEN(f.control, info, 1)) THEN Fail("error writing file", f) END;
      f.open := TRUE; f.writable := TRUE
    END
  END MakeWritable;

  (* The bytes of f's block not written out written to its file. *)
  PROCEDURE Flush(f: File);
    VAR count: LONGINT;
  BEGIN
    IF f.dirty THEN
      count := f.length - f.blockStart;
      IF count > blockSize THEN count := blockSize END;
      IF ~ODD(POC_FILE_WRITE(f.control, f.blockStart, f.block, SHORT(count))) THEN
        Fail("error writing file", f)
      END;
      IF f.blockStart + count > f.onDisk THEN f.onDisk := f.blockStart + count END;
      f.dirty := FALSE
    END
  END Flush;

  (* f's block made the one holding the byte at position *)
  PROCEDURE Load(f: File; position: LONGINT);
    VAR start: LONGINT;
  BEGIN
    start := position - position MOD blockSize;
    IF f.blockStart # start THEN
      Flush(f);
      IF start < f.onDisk THEN
        Open(f);
        IF ~ODD(POC_FILE_READ(f.control, start, f.block)) THEN Fail("error reading file", f) END
      END;
      f.blockStart := start
    END
  END Load;

  (* The next record of a file read by record made the current one; FALSE
     at the end of the file. *)
  PROCEDURE NextRecord(f: File): BOOLEAN;
    VAR n: INTEGER;
  BEGIN
    n := POC_FILE_GET(f.control, f.record^, recordSize);
    IF n = -1 THEN RETURN FALSE
    ELSIF n < 0 THEN Fail("error reading file", f)
    END;
    f.recordStart := f.recordStart + f.recordLength;
    f.recordLength := n; INC(f.recordLength); (* a LONGINT: a word under -O2 cannot hold 32767 + 1 *)
    RETURN TRUE
  END NextRecord;

  (* A file read by record back before its first record. *)
  PROCEDURE Rewind(f: File);
  BEGIN
    IF ~ODD(POC_FILE_REWIND(f.control)) THEN Fail("error reading file", f) END;
    f.recordStart := 0; f.recordLength := 0
  END Rewind;

  (* The byte at position of a file read by record, position < length:
     the record's, or the LF after it *)
  PROCEDURE RecordByte(f: File; position: LONGINT; VAR x: SYSTEM.BYTE);
  BEGIN
    IF ~f.open THEN Open(f); f.recordStart := 0; f.recordLength := 0 END;
    IF position < f.recordStart THEN Rewind(f) END;
    WHILE position >= f.recordStart + f.recordLength DO
      IF ~NextRecord(f) THEN Fail("error reading file", f) END
    END;
    IF position - f.recordStart < f.recordLength - 1 THEN x := f.record[position - f.recordStart]
    ELSE x := 0AX
    END
  END RecordByte;

  (* The collector's finalizer of a File (FINALIZATION above): what can
     be done is done, and nothing stops the program. *)
  PROCEDURE Finalize(obj: SYSTEM.PTR);
    VAR f: File; count: LONGINT; status: INTEGER; temporary: Name;
  BEGIN
    f := SYSTEM.VAL(File, obj);
    IF f.dirty & f.open THEN
      count := f.length - f.blockStart;
      IF count > blockSize THEN count := blockSize END;
      status := POC_FILE_WRITE(f.control, f.blockStart, f.block, SHORT(count));
      f.dirty := FALSE
    END;
    IF f.open THEN status := POC_FILE_CLOSE(f.control); f.open := FALSE END;
    IF f.isNew & f.created THEN
      status := POC_FILE_NAME(f.control, temporary, nameLength - 1);
      IF status > 0 THEN status := POC_ERASE(temporary, status) END
    END
  END Finalize;

  PROCEDURE NewFile(VAR name: Name): File;
    VAR f: File;
  BEGIN
    NEW(f);
    COPY(name, f.name);
    f.blockStart := -1;
    GarbageCollectedHeap.RegisterFinalizer(f, Finalize);
    RETURN f
  END NewFile;

  (* A new, empty file, to be called name once registered (NEW AND
     REGISTER above); nothing is made on disk until it is written to,
     closed or registered. *)
  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File; s: Name; n: INTEGER;
  BEGIN
    IF ~CopyName(name, s, n) THEN Fail("file name too long", NIL) END;
    f := NewFile(s);
    f.isNew := TRUE;
    n := POC_EXPAND_NAME(s, n, f.registerName, nameLength - 1);
    IF n >= 0 THEN f.registerName[n] := 0X
    ELSE f.registerName := s (* not parsed: Create says why *)
    END;
    RETURN f
  END New;

  (* The file at path opened to be read, or NIL; name is the name it was
     asked for by. *)
  PROCEDURE OpenOld(VAR path: Name; VAR name: ARRAY OF CHAR): File;
    VAR f: File; s: Name; n: INTEGER; info: Info; block: LONGINT;
  BEGIN
    IF ~CopyName(name, s, n) THEN RETURN NIL END;
    f := NewFile(s);
    IF ~ODD(POC_FILE_OPEN(f.control, path, Length0X(path), info)) THEN RETURN NIL END;
    f.open := TRUE; f.created := TRUE;
    IF info[0] = 1 THEN
      block := info[1];
      IF block > 0 THEN f.length := (block - 1) * blockSize + info[2] END
    ELSE
      f.byRecord := TRUE;
      NEW(f.record);
      WHILE NextRecord(f) DO END;
      f.length := f.recordStart + f.recordLength;
      Rewind(f)
    END;
    f.onDisk := f.length;
    RETURN f
  END OpenOld;

  (* Whether name says where it is: a device or logical name, or a
     directory *)
  PROCEDURE HasDirectory(VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) DO
      IF (name[i] = ":") OR (name[i] = "[") OR (name[i] = "<") THEN RETURN TRUE END;
      INC(i)
    END;
    RETURN FALSE
  END HasDirectory;

  (* The next directory of the search path from position, in dir ("" when
     there are no more), as voc's ScanPath, "~" standing for SYS$LOGIN
     (OLD AND THE SEARCH PATH above) *)
  PROCEDURE NextDirectory(VAR position: LONGINT; VAR dir: Name);
    VAR i: LONGINT; ch: CHAR;
  BEGIN
    i := 0;
    ch := searchPath[position];
    WHILE (ch = " ") OR (ch = ",") DO INC(position); ch := searchPath[position] END;
    IF ch = "~" THEN
      INC(position); ch := searchPath[position];
      WHILE (home[i] # 0X) & (i < nameLength - 1) DO dir[i] := home[i]; INC(i) END;
      (* "~[.LIB]": the directory LIB inside SYS$LOGIN's *)
      IF (ch = "[") & (searchPath[position + 1] = ".") & (i > 0) & (dir[i - 1] = "]") THEN
        DEC(i); INC(position); ch := searchPath[position]
      END
    END;
    WHILE (ch # 0X) & (ch # ",") DO
      IF i < nameLength - 1 THEN dir[i] := ch; INC(i) END;
      INC(position); ch := searchPath[position]
    END;
    WHILE (i > 0) & (dir[i - 1] = " ") DO DEC(i) END;
    dir[i] := 0X
  END NextDirectory;

  (* path := dir and name, a ":" between them when dir is a logical name
     (it does not end in "]", ">" or ":"); FALSE if it would not fit *)
  PROCEDURE JoinPath(VAR dir: Name; VAR name: ARRAY OF CHAR; VAR path: Name): BOOLEAN;
    VAR i, k, n: LONGINT; last: CHAR;
  BEGIN
    i := Length0X(dir);
    n := Length0X(name);
    IF i + 1 + n >= nameLength THEN RETURN FALSE END;
    FOR k := 0 TO i - 1 DO path[k] := dir[k] END;
    last := dir[i - 1];
    IF (last # "]") & (last # ">") & (last # ":") THEN path[i] := ":"; INC(i) END;
    FOR k := 0 TO n - 1 DO path[i + k] := name[k] END;
    path[i + n] := 0X;
    RETURN TRUE
  END JoinPath;

  (* The file called name, opened to be read, or NIL if there is none or it
     cannot be read (OLD AND THE SEARCH PATH above). *)
  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File; path, dir: Name; position: LONGINT; n: INTEGER;
  BEGIN
    f := NIL;
    IF CopyName(name, path, n) THEN
      IF HasDirectory(name) OR (searchPath = NIL) THEN
        f := OpenOld(path, name)
      ELSE
        position := 0;
        NextDirectory(position, dir);
        WHILE (f = NIL) & (dir[0] # 0X) DO
          IF JoinPath(dir, name, path) THEN f := OpenOld(path, name) END;
          NextDirectory(position, dir)
        END
      END
    END;
    RETURN f
  END Old;

  (* Writes out what is buffered and closes the file; f can still be used,
     opening it again. A New file that was never written to is made,
     empty. *)
  PROCEDURE Close*(f: File);
  BEGIN
    IF f.isNew THEN Create(f) END;
    Flush(f);
    IF f.open THEN
      IF ~ODD(POC_FILE_CLOSE(f.control)) THEN Fail("error writing file", f) END;
      f.open := FALSE; f.writable := FALSE
    END
  END Close;

  (* Closes f, and if it came from New gives it its name, as a new
     version. *)
  PROCEDURE Register*(f: File);
  BEGIN
    Close(f);
    IF f.isNew THEN
      IF ~ODD(POC_FILE_RENAME(f.control, f.registerName, Length0X(f.registerName))) THEN
        Fail("could not rename temporary file as its registered name", f)
      END;
      f.isNew := FALSE
    END
  END Register;

  (* The number of bytes in f. *)
  PROCEDURE Length*(f: File): LONGINT;
  BEGIN
    RETURN f.length
  END Length;

  (* Empties f: its length is 0, by a write of no bytes at its start with
     truncate-on-put. *)
  PROCEDURE Purge*(f: File);
    VAR start: LONGINT;
  BEGIN
    IF f.created THEN
      MakeWritable(f);
      start := 0;
      IF ~ODD(POC_FILE_TRUNCATE(f.control, start, f.block, 0)) THEN Fail("file not truncated", f) END;
      f.dirty := FALSE; f.blockStart := -1; f.onDisk := 0
    END;
    f.length := 0
  END Purge;

  (* The time and date f was last changed, in Oberon's clock format
     (Platform.GetClock): its revision date, or, when it is open to be
     written, now, since RMS dates it when it is closed. A New file not yet
     written to is created first, as rtl/llvm's is. *)
  PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
    VAR identity: Platform.FileIdentity;
  BEGIN
    IF ~f.created THEN Create(f) END;
    IF f.writable THEN Platform.GetClock(t, d)
    ELSE
      Open(f);
      IF ~ODD(POC_FILE_IDENTITY(f.control, identity)) THEN Fail("file not identified", f) END;
      Platform.MTimeAsClock(identity, t, d)
    END
  END GetDate;

  (* The name f was asked for by (Old) or registered under (New and
     Register); a New file not registered yet: its temporary file's full
     name, "" if it has none yet. *)
  PROCEDURE GetName*(f: File; VAR name: ARRAY OF CHAR);
    VAR temporary: Name; n: INTEGER;
  BEGIN
    IF ~f.isNew THEN COPY(f.name, name)
    ELSIF f.created THEN
      n := POC_FILE_NAME(f.control, temporary, nameLength - 1);
      temporary[n] := 0X;
      COPY(temporary, name)
    ELSIF LEN(name) > 0 THEN name[0] := 0X
    END
  END GetName;

  (* Points r at position pos of f (0 if it is negative, the end if it is
     past the end) and clears its eof and res. *)
  PROCEDURE Set*(VAR r: Rider; f: File; pos: LONGINT);
  BEGIN
    IF f = NIL THEN pos := 0
    ELSIF pos > f.length THEN pos := f.length
    ELSIF pos < 0 THEN pos := 0
    END;
    r.file := f;
    r.position := pos;
    r.eof := FALSE;
    r.res := 0
  END Set;

  (* r's position in its file. *)
  PROCEDURE Pos*(VAR r: Rider): LONGINT;
  BEGIN
    RETURN r.position
  END Pos;

  (* The file r is on. *)
  PROCEDURE Base*(VAR r: Rider): File;
  BEGIN
    RETURN r.file
  END Base;

  (* The byte at r's position, and on to the next. At the end of the file x
     is 0X and r.eof is set. *)
  PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);
    VAR f: File;
  BEGIN
    f := r.file;
    IF r.position < f.length THEN
      IF f.byRecord THEN RecordByte(f, r.position, x)
      ELSE Load(f, r.position); x := f.block[r.position - f.blockStart]
      END;
      INC(r.position)
    ELSE
      x := 0X; r.eof := TRUE
    END
  END Read;

  (* x at r's position, overwriting the byte there or, at the end,
     extending the file, and on to the next. A New file is made on disk at
     the first write, as rtl/llvm's is, so that one that cannot be is
     reported there, not when its block is written out. *)
  PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
    VAR f: File;
  BEGIN
    f := r.file;
    MakeWritable(f);
    Load(f, r.position);
    f.block[r.position - f.blockStart] := x;
    f.dirty := TRUE;
    INC(r.position);
    IF r.position > f.length THEN f.length := r.position END;
    r.res := 0
  END Write;

  (* Read, by the name Project Oberon's Files has *)
  PROCEDURE ReadByte*(VAR r: Rider; VAR x: SYSTEM.BYTE);
  BEGIN
    Read(r, x)
  END ReadByte;

  (* n bytes into x from its start; r.res is how many of them were not
     there to read, and r.eof is set if any. n larger than x traps (index
     out of range), as voc's does. *)
  PROCEDURE ReadBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
    VAR got: LONGINT; outside: SYSTEM.BYTE;
  BEGIN
    IF n > LEN(x) THEN outside := x[n - 1] END;
    got := 0;
    IF n > 0 THEN
      WHILE (got < n) & (r.position < r.file.length) DO Read(r, x[got]); INC(got) END
    ELSE
      n := 0
    END;
    r.res := n - got;
    r.eof := r.res > 0
  END ReadBytes;

  (* The first n bytes of x; n larger than x traps, as in ReadBytes. *)
  PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
    VAR i: LONGINT; outside: SYSTEM.BYTE;
  BEGIN
    IF n > LEN(x) THEN outside := x[n - 1] END;
    FOR i := 0 TO n - 1 DO Write(r, x[i]) END;
    r.res := 0
  END WriteBytes;

  (* The characters of x up to and including its 0X (all of x if it has
     none), the terminator written, as rtl/llvm's writes it, so that
     ReadString finds where the string ends. *)
  PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(x)) & (x[i] # 0X) DO Write(r, x[i]); INC(i) END;
    IF i < LEN(x) THEN Write(r, 0X) END
  END WriteString;

  (* Reads up to the next 0X (or the end of the file) into x, cutting it
     short if x cannot hold it all. *)
  PROCEDURE ReadString*(VAR r: Rider; VAR x: ARRAY OF CHAR);
    VAR i: LONGINT; ch: CHAR;
  BEGIN
    i := 0;
    LOOP
      Read(r, ch);
      IF ch = 0X THEN EXIT END;
      IF i < LEN(x) - 1 THEN x[i] := ch; INC(i) END
    END;
    x[i] := 0X
  END ReadString;

  (* Reads up to the next line feed (or 0X, or the end of the file) into
     x, without the line feed or a carriage return before it; a line too
     long for x is cut short. At the end of the file r.eof is set, so a
     last line with no line feed after it is returned with r.eof set. *)
  PROCEDURE ReadLine*(VAR r: Rider; VAR x: ARRAY OF CHAR);
    VAR i: LONGINT; ch: CHAR;
  BEGIN
    i := 0;
    LOOP
      Read(r, ch);
      IF (ch = 0X) OR (ch = 0AX) THEN EXIT END;
      IF i < LEN(x) - 1 THEN x[i] := ch; INC(i) END
    END;
    IF (ch = 0AX) & (i > 0) & (x[i - 1] = 0DX) THEN DEC(i) END;
    x[i] := 0X
  END ReadLine;

  (* Deletes the file called name, the highest version when it gives none;
     res is 0 if it did, else the error code (Platform.ErrorCode). *)
  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Unlink(name)
  END Delete;

  (* Renames the file old to new, as a new version of new; res is 0 if it
     did, else the error code (Platform.ErrorCode). *)
  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Rename(old, new)
  END Rename;

  (* Makes path the default directory; res is 0 if it did, else the error
     code. A name given to Old or New after it is taken from there. *)
  PROCEDURE ChangeDirectory*(path: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Chdir(path)
  END ChangeDirectory;

  (* The directories Old looks in for a name that does not say where it is
     (OLD AND THE SEARCH PATH above); "" for just the default directory
     again. *)
  PROCEDURE SetSearchPath*(path: ARRAY OF CHAR);
    VAR n: LONGINT;
  BEGIN
    n := Length0X(path);
    IF n = 0 THEN searchPath := NIL
    ELSE NEW(searchPath, n + 1); COPY(path, searchPath^)
    END
  END SetSearchPath;

  (* ---- the typed riders (THE TYPED RIDERS above) ---- *)

  (* A byte as a signed number, -128..127 *)
  PROCEDURE Signed(ch: CHAR): INTEGER;
  BEGIN
    IF ORD(ch) >= 128 THEN RETURN ORD(ch) - 256 ELSE RETURN ORD(ch) END
  END Signed;

  (* 2 to the power n, as a HUGEINT *)
  PROCEDURE PowerOfTwo(n: INTEGER): HUGEINT;
    VAR one: HUGEINT;
  BEGIN
    one := 1;
    RETURN ASH(one, n)
  END PowerOfTwo;

  (* m shifted right by shift > 0, rounded to nearest, ties to even *)
  PROCEDURE ShiftRounded(m: HUGEINT; shift: INTEGER): HUGEINT;
    VAR q, rest, half: HUGEINT;
  BEGIN
    q := ASH(m, -shift);
    rest := m - ASH(q, shift);
    half := PowerOfTwo(shift - 1);
    IF (rest > half) OR (rest = half) & ODD(q) THEN INC(q) END;
    RETURN q
  END ShiftRounded;

  (* A VAX value's sign, exponent and fraction, of fractionBits bits, as
     IEEE's of the same widths: the exponent 2 less, a value too small
     for IEEE's normal range a denormal, rounded, and the reserved operand
     (sign 1, exponent 0) a NaN *)
  PROCEDURE VaxToIeee(VAR sign, exponent: INTEGER; VAR fraction: HUGEINT; fractionBits, maxExponent: INTEGER);
    VAR hidden: HUGEINT;
  BEGIN
    hidden := PowerOfTwo(fractionBits);
    IF exponent = 0 THEN
      IF sign = 1 THEN exponent := maxExponent; fraction := ASH(hidden, -1) END;
      sign := 0
    ELSIF exponent > 2 THEN
      DEC(exponent, 2)
    ELSE
      fraction := ShiftRounded(hidden + fraction, 3 - exponent);
      exponent := 0;
      IF fraction >= hidden THEN exponent := 1; DEC(fraction, hidden) END
    END
  END VaxToIeee;

  (* An IEEE value's sign, exponent and fraction as the VAX's (THE TYPED
     RIDERS above) *)
  PROCEDURE IeeeToVax(VAR sign, exponent: INTEGER; VAR fraction: HUGEINT; fractionBits, maxExponent: INTEGER);
  BEGIN
    IF exponent = 0 THEN
      sign := 0; fraction := 0
    ELSIF (exponent = maxExponent) & (fraction # 0) THEN
      sign := 1; exponent := 0; fraction := 0
    ELSIF exponent + 2 > maxExponent THEN
      exponent := maxExponent; fraction := PowerOfTwo(fractionBits) - 1
    ELSE
      INC(exponent, 2)
    END
  END IeeeToVax;

  (* An IEEE single in Oakwood's little-endian bytes, taken apart and put
     together *)
  PROCEDURE SingleFields(VAR b: ARRAY OF CHAR; VAR sign, exponent: INTEGER; VAR fraction: HUGEINT);
  BEGIN
    sign := ORD(b[3]) DIV 128;
    exponent := ORD(b[3]) MOD 128 * 2 + ORD(b[2]) DIV 128;
    fraction := (LONG(ORD(b[2]) MOD 128) * 256 + ORD(b[1])) * 256 + ORD(b[0])
  END SingleFields;

  PROCEDURE SingleBytes(sign, exponent: INTEGER; fraction: HUGEINT; VAR b: ARRAY OF CHAR);
  BEGIN
    b[3] := CHR(sign * 128 + exponent DIV 2);
    b[2] := CHR(exponent MOD 2 * 128 + SHORT(SHORT(ASH(fraction, -16))));
    b[1] := CHR(SHORT(SHORT(ASH(fraction, -8) MOD 256)));
    b[0] := CHR(SHORT(SHORT(fraction MOD 256)))
  END SingleBytes;

  (* An F_floating value's bytes, two words with the high one first, taken
     apart and put together *)
  PROCEDURE FFields(VAR v: ARRAY OF CHAR; VAR sign, exponent: INTEGER; VAR fraction: HUGEINT);
  BEGIN
    sign := ORD(v[1]) DIV 128;
    exponent := ORD(v[1]) MOD 128 * 2 + ORD(v[0]) DIV 128;
    fraction := (LONG(ORD(v[0]) MOD 128) * 256 + ORD(v[3])) * 256 + ORD(v[2])
  END FFields;

  PROCEDURE FBytes(sign, exponent: INTEGER; fraction: HUGEINT; VAR v: ARRAY OF CHAR);
  BEGIN
    v[1] := CHR(sign * 128 + exponent DIV 2);
    v[0] := CHR(exponent MOD 2 * 128 + SHORT(SHORT(ASH(fraction, -16))));
    v[3] := CHR(SHORT(SHORT(ASH(fraction, -8) MOD 256)));
    v[2] := CHR(SHORT(SHORT(fraction MOD 256)))
  END FBytes;

  (* An IEEE double in Oakwood's little-endian bytes, taken apart and put
     together *)
  PROCEDURE DoubleFields(VAR b: ARRAY OF CHAR; VAR sign, exponent: INTEGER; VAR fraction: HUGEINT);
    VAR i: INTEGER;
  BEGIN
    sign := ORD(b[7]) DIV 128;
    exponent := ORD(b[7]) MOD 128 * 16 + ORD(b[6]) DIV 16;
    fraction := ORD(b[6]) MOD 16;
    FOR i := 5 TO 0 BY -1 DO fraction := fraction * 256 + ORD(b[i]) END
  END DoubleFields;

  PROCEDURE DoubleBytes(sign, exponent: INTEGER; fraction: HUGEINT; VAR b: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    b[7] := CHR(sign * 128 + exponent DIV 16);
    b[6] := CHR(exponent MOD 16 * 16 + SHORT(SHORT(ASH(fraction, -48))));
    FOR i := 0 TO 5 DO b[i] := CHR(SHORT(SHORT(ASH(fraction, -8 * i) MOD 256))) END
  END DoubleBytes;

  (* A G_floating value's bytes, four words with the highest first, taken
     apart and put together *)
  PROCEDURE GFields(VAR v: ARRAY OF CHAR; VAR sign, exponent: INTEGER; VAR fraction: HUGEINT);
    VAR i: INTEGER;
  BEGIN
    sign := ORD(v[1]) DIV 128;
    exponent := ORD(v[1]) MOD 128 * 16 + ORD(v[0]) DIV 16;
    fraction := ORD(v[0]) MOD 16;
    FOR i := 1 TO 3 DO fraction := (fraction * 256 + ORD(v[2 * i + 1])) * 256 + ORD(v[2 * i]) END
  END GFields;

  PROCEDURE GBytes(sign, exponent: INTEGER; fraction: HUGEINT; VAR v: ARRAY OF CHAR);
    VAR i: INTEGER; word: HUGEINT;
  BEGIN
    v[1] := CHR(sign * 128 + exponent DIV 16);
    v[0] := CHR(exponent MOD 16 * 16 + SHORT(SHORT(ASH(fraction, -48))));
    FOR i := 1 TO 3 DO
      word := ASH(fraction, -16 * (3 - i)) MOD 65536;
      v[2 * i + 1] := CHR(SHORT(SHORT(word DIV 256)));
      v[2 * i] := CHR(SHORT(SHORT(word MOD 256)))
    END
  END GBytes;

  (* The typed riders: a value in the external format (THE TYPED RIDERS
     above) at r's position, and on past it; at the end of the file r.eof
     is set, as by Read. *)
  PROCEDURE ReadBool*(VAR r: Rider; VAR x: BOOLEAN);
    VAR ch: CHAR;
  BEGIN
    Read(r, ch); x := ch # 0X
  END ReadBool;

  PROCEDURE ReadInt*(VAR r: Rider; VAR x: INTEGER);
    VAR b: ARRAY 2 OF CHAR;
  BEGIN
    ReadBytes(r, b, 2);
    x := Signed(b[1]) * 256 + ORD(b[0])
  END ReadInt;

  PROCEDURE ReadLInt*(VAR r: Rider; VAR x: LONGINT);
    VAR b: ARRAY 4 OF CHAR;
  BEGIN
    ReadBytes(r, b, 4);
    x := ((LONG(Signed(b[3])) * 256 + ORD(b[2])) * 256 + ORD(b[1])) * 256 + ORD(b[0])
  END ReadLInt;

  PROCEDURE ReadSet*(VAR r: Rider; VAR x: SET);
    VAR b: ARRAY 4 OF CHAR; i: INTEGER;
  BEGIN
    ReadBytes(r, b, 4);
    x := {};
    FOR i := 0 TO 31 DO
      IF ODD(ASH(ORD(b[i DIV 8]), -(i MOD 8))) THEN INCL(x, i) END
    END
  END ReadSet;

  PROCEDURE ReadReal*(VAR r: Rider; VAR x: REAL);
    VAR b, v: ARRAY 4 OF CHAR; sign, exponent: INTEGER; fraction: HUGEINT;
  BEGIN
    ReadBytes(r, b, 4);
    SingleFields(b, sign, exponent, fraction);
    IeeeToVax(sign, exponent, fraction, 23, 255);
    FBytes(sign, exponent, fraction, v);
    SYSTEM.MOVE(SYSTEM.ADR(v), SYSTEM.ADR(x), 4)
  END ReadReal;

  PROCEDURE ReadLReal*(VAR r: Rider; VAR x: LONGREAL);
    VAR b, v: ARRAY 8 OF CHAR; sign, exponent: INTEGER; fraction: HUGEINT;
  BEGIN
    ReadBytes(r, b, 8);
    DoubleFields(b, sign, exponent, fraction);
    IeeeToVax(sign, exponent, fraction, 52, 2047);
    GBytes(sign, exponent, fraction, v);
    SYSTEM.MOVE(SYSTEM.ADR(v), SYSTEM.ADR(x), 8)
  END ReadLReal;

  (* A number WriteNum wrote, into x, which may be any integer variable of
     at most 8 bytes: its low bytes, as voc's. *)
  PROCEDURE ReadNum*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE);
    VAR ch: CHAR; shift: INTEGER; q, part: SYSTEM.INT64; i: LONGINT;
  BEGIN
    ASSERT(LEN(x) <= 8);
    shift := 0; q := 0;
    Read(r, ch);
    WHILE ORD(ch) >= 128 DO
      part := ORD(ch) - 128; q := q + ASH(part, shift);
      INC(shift, 7);
      Read(r, ch)
    END;
    part := ORD(ch) MOD 64 - ORD(ch) DIV 64 * 64; q := q + ASH(part, shift);
    FOR i := 0 TO LEN(x) - 1 DO SYSTEM.PUT(SYSTEM.ADR(x) + i, CHR(q MOD 256)); q := ASH(q, -8) END
  END ReadNum;

  (* The typed riders: x in the external format (THE TYPED RIDERS above)
     at r's position, and on past it. *)
  PROCEDURE WriteBool*(VAR r: Rider; x: BOOLEAN);
  BEGIN
    IF x THEN Write(r, 1X) ELSE Write(r, 0X) END
  END WriteBool;

  PROCEDURE WriteInt*(VAR r: Rider; x: INTEGER);
    VAR b: ARRAY 2 OF CHAR;
  BEGIN
    b[0] := CHR(x MOD 256); b[1] := CHR(x DIV 256 MOD 256);
    WriteBytes(r, b, 2)
  END WriteInt;

  PROCEDURE WriteLInt*(VAR r: Rider; x: LONGINT);
    VAR b: ARRAY 4 OF CHAR; i: INTEGER;
  BEGIN
    FOR i := 0 TO 3 DO b[i] := CHR(x MOD 256); x := x DIV 256 END;
    WriteBytes(r, b, 4)
  END WriteLInt;

  PROCEDURE WriteSet*(VAR r: Rider; x: SET);
    VAR b: ARRAY 4 OF CHAR; i, k: INTEGER;
  BEGIN
    FOR k := 0 TO 3 DO
      b[k] := 0X;
      FOR i := 7 TO 0 BY -1 DO
        b[k] := CHR(ORD(b[k]) * 2);
        IF k * 8 + i IN x THEN b[k] := CHR(ORD(b[k]) + 1) END
      END
    END;
    WriteBytes(r, b, 4)
  END WriteSet;

  PROCEDURE WriteReal*(VAR r: Rider; x: REAL);
    VAR b, v: ARRAY 4 OF CHAR; sign, exponent: INTEGER; fraction: HUGEINT;
  BEGIN
    SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(v), 4);
    FFields(v, sign, exponent, fraction);
    VaxToIeee(sign, exponent, fraction, 23, 255);
    SingleBytes(sign, exponent, fraction, b);
    WriteBytes(r, b, 4)
  END WriteReal;

  PROCEDURE WriteLReal*(VAR r: Rider; x: LONGREAL);
    VAR b, v: ARRAY 8 OF CHAR; sign, exponent: INTEGER; fraction: HUGEINT;
  BEGIN
    SYSTEM.MOVE(SYSTEM.ADR(x), SYSTEM.ADR(v), 8);
    GFields(v, sign, exponent, fraction);
    VaxToIeee(sign, exponent, fraction, 52, 2047);
    DoubleBytes(sign, exponent, fraction, b);
    WriteBytes(r, b, 8)
  END WriteLReal;

  (* x as a variable-length number (THE TYPED RIDERS above), which
     ReadNum reads back. *)
  PROCEDURE WriteNum*(VAR r: Rider; x: SYSTEM.INT64);
  BEGIN
    WHILE (x < -64) OR (x > 63) DO
      Write(r, CHR(x MOD 128 + 128)); x := x DIV 128
    END;
    Write(r, CHR(x MOD 128))
  END WriteNum;

BEGIN
  MaxPathLength := Platform.MaxPathLength();
  MaxNameLength := Platform.MaxNameLength();
  Platform.GetEnv("SYS$LOGIN", home)
END Files.
