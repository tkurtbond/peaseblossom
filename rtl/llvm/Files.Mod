MODULE Files;

  (* PLAN.md Phase 10 step 3: Oberon files - the Oakwood Guidelines' Files
     module as voc has it (src/runtime/Files.Mod), reduced to what poc's own
     source calls plus a few of its neighbours: File and Rider, New, Old,
     Register, Close, Length, Set, Pos, Base, Read, Write, ReadString,
     ReadLine, WriteString, Delete and Rename. Not here: the typed
     read/write procedures (ReadInt, WriteReal, ...), ReadBytes/WriteBytes
     and Purge, GetDate, GetName and SetSearchPath. Read and Write take a
     CHAR where voc's take SYSTEM.BYTE, which poc has had since Phase 10
     step 7; changing them is a Phase 11 question (a BYTE is not a CHAR).

     THE MODEL. A File is a byte sequence with a length; a Rider is a
     position in one (r.position, set by Set) and the result of the last
     operation (r.eof, r.res). Set clamps a position into 0..Length, so a
     file has no holes; Write at the end extends the file, Write inside it
     overwrites. Several riders may share a file and see each other's
     writes at once.

     A File does not keep its own buffers: it holds a C stdio stream, and
     libc does the buffering. Every operation says where it means to
     work, and the file seeks when the stream is somewhere else or was last
     used the other way (C requires a seek between a read and a write).
     stdio is what makes this portable. open(2) and lseek(2) are not the
     same on Linux and the three BSDs: O_CREAT and O_TRUNC have different
     values, and lseek's off_t is 32 bits on 32-bit Linux but 64 on 32-bit
     NetBSD, OpenBSD and FreeBSD (the BSD half from memory, to be confirmed
     on those systems), with no conditional compilation to choose between
     them. fopen takes a mode *string*, and fseek a `long`, which
     is a word on every one of them - so a file is limited to what a
     LONGINT holds (2 GB under the -O2 size model), as in voc.

     NEW AND REGISTER. New creates nothing on disk. The first write (or
     Close, or Register) creates a temporary file in the directory of the
     name given to New - ".tmp.<n>.<pid>", so it cannot collide with a
     real file - and Register renames it to that name, replacing any file
     already there in one step: a reader never sees a half-written result,
     and a compiler that stops half way leaves the old file. Every name is
     made absolute when it is given (from Platform.CWD), so a program that
     changes directory between New and Register still registers where it
     meant to. A New file never registered leaves its temporary file
     behind, if anything was written to it (voc deletes it when the
     garbage collector finalizes the File; this collector does not
     finalize).

     OPEN STREAMS. Close writes everything out and closes the stream, but
     the File stays usable: the next operation reopens it. That keeps a
     program that opens many files from running out of descriptors even
     though nothing here finalizes a File that is dropped without Close
     (its stream stays open until the program ends, and unwritten data is
     lost, as with voc's).

     Where this differs from voc's, besides the missing procedures:
     - two Old calls for one file give two independent Files (voc shares
       one, so a write through one is at once visible through the other);
       after a Register over a file that another File has open, that File
       keeps reading the old contents;
     - ReadString and ReadLine cut a value too long for the array short
       (and ReadLine skips the rest of the line) where voc overruns it;
     - an error that cannot be reported to the caller - a file that cannot
       be created, a failed write - stops the program with a message and
       Halt(99), as voc does; Delete and Rename report failure as -1
       rather than errno (see Platform.Mod);
     - the C `int` results below are declared LONGINT, right under the -O2
       size model only (see Platform.Mod). *)

  IMPORT SYSTEM, Platform, Console;

  CONST
    nameLength = 256;
    seekSet = 0;
    seekEnd = 2;
    (* what the stream was last used for *)
    unused = 0;
    reading = 1;
    writing = 2;

  TYPE
    FileName = ARRAY nameLength OF CHAR;
    File* = POINTER TO FileDesc;
    FileDesc = RECORD
      workName: FileName; (* the OS file: a temporary one until Register *)
      registerName: FileName; (* the name to Register under, "" once done *)
      stream: SYSTEM.ADDRESS; (* the C FILE, 0 while closed *)
      created: BOOLEAN; (* whether an OS file exists under workName *)
      length: LONGINT;
      position: LONGINT; (* where the stream is, unless mode = unused *)
      mode: INTEGER
    END;
    Rider* = RECORD
      res*: LONGINT; (* 0 after a successful operation *)
      eof*: BOOLEAN; (* set when a read went past the end *)
      file: File;
      position: LONGINT
    END;

  VAR
    temporaryCount: LONGINT;

  PROCEDURE ["C", "fopen"] FOpen(path, mode: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "fclose"] FClose(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "fflush"] FFlush(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "fread"] FRead(buffer, size, count, stream: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "fwrite"] FWrite(buffer, size, count, stream: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "fseek"] FSeek(stream, offset: SYSTEM.ADDRESS; whence: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "ferror"] FError(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "ftell"] FTell(stream: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "rename"] CRename(old, new: SYSTEM.ADDRESS): SYSTEM.INT32;
  (* Directory detection for Old (see IsDirectory's own comment). *)
  PROCEDURE ["C", "access"] Access(path: SYSTEM.ADDRESS; mode: SYSTEM.INT32): SYSTEM.INT32;

  (* An error nothing above can be told about: says what and where, and
     stops the program. *)
  PROCEDURE Fail(message: ARRAY OF CHAR; f: File);
  BEGIN
    Console.Ln; Console.String("-- "); Console.String(message);
    IF f # NIL THEN
      Console.String(": ");
      IF f.registerName[0] # 0X THEN Console.String(f.registerName)
      ELSE Console.String(f.workName)
      END
    END;
    Console.Ln;
    HALT(99)
  END Fail;

  PROCEDURE StringLength(s: ARRAY OF CHAR): LONGINT;
    VAR n: LONGINT;
  BEGIN
    n := 0;
    WHILE (n < LEN(s)) & (s[n] # 0X) DO INC(n) END;
    RETURN n
  END StringLength;

  (* dest := name, as an absolute path if it is not one; a name that does
     not fit is fatal *)
  PROCEDURE MakeAbsolute(name: ARRAY OF CHAR; VAR dest: FileName);
    VAR n, c, k: LONGINT;
  BEGIN
    n := StringLength(name);
    c := StringLength(Platform.CWD);
    IF ((n > 0) & (name[0] = "/")) OR (c = 0) THEN
      IF n >= nameLength THEN Fail("file name too long", NIL) END;
      COPY(name, dest)
    ELSE
      IF c + 1 + n >= nameLength THEN Fail("file name too long", NIL) END;
      COPY(Platform.CWD, dest);
      k := c;
      IF dest[k - 1] # "/" THEN dest[k] := "/"; INC(k) END;
      c := 0;
      WHILE c < n DO dest[k] := name[c]; INC(k); INC(c) END;
      dest[k] := 0X
    END
  END MakeAbsolute;

  PROCEDURE AppendText(VAR s: FileName; VAR k: LONGINT; text: ARRAY OF CHAR);
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE text[i] # 0X DO s[k] := text[i]; INC(k); INC(i) END
  END AppendText;

  (* n >= 0 in decimal *)
  PROCEDURE AppendNumber(VAR s: FileName; VAR k: LONGINT; n: LONGINT);
    VAR digits: ARRAY 12 OF CHAR; count: LONGINT;
  BEGIN
    count := 0;
    REPEAT digits[count] := CHR(ORD("0") + n MOD 10); n := n DIV 10; INC(count) UNTIL n = 0;
    WHILE count > 0 DO DEC(count); s[k] := digits[count]; INC(k) END
  END AppendNumber;

  (* f.workName := a fresh name next to the file f is to be registered as *)
  PROCEDURE MakeTemporaryName(f: File);
    VAR i, last, k: LONGINT;
  BEGIN
    last := 0; i := 0;
    WHILE f.registerName[i] # 0X DO
      IF f.registerName[i] = "/" THEN last := i END;
      INC(i)
    END;
    IF last + 40 >= nameLength THEN Fail("file name too long", f) END;
    FOR i := 0 TO last DO f.workName[i] := f.registerName[i] END;
    k := last + 1;
    INC(temporaryCount);
    AppendText(f.workName, k, ".tmp.");
    AppendNumber(f.workName, k, temporaryCount);
    AppendText(f.workName, k, ".");
    AppendNumber(f.workName, k, Platform.PID);
    f.workName[k] := 0X
  END MakeTemporaryName;

  PROCEDURE OpenStream(VAR name: FileName; mode: ARRAY OF CHAR): SYSTEM.ADDRESS;
  BEGIN
    RETURN FOpen(SYSTEM.ADR(name), SYSTEM.ADR(mode))
  END OpenStream;

  (* Makes sure f has an open stream: creates the temporary file of a New
     file that has none yet, reopens one that was closed. *)
  PROCEDURE EnsureOpen(f: File);
  BEGIN
    IF f.stream = 0 THEN
      IF ~f.created THEN
        MakeTemporaryName(f);
        f.stream := OpenStream(f.workName, "w+b");
        IF f.stream = 0 THEN Fail("file not created", f) END;
        f.created := TRUE
      ELSE
        f.stream := OpenStream(f.workName, "r+b");
        IF f.stream = 0 THEN f.stream := OpenStream(f.workName, "rb") END;
        IF f.stream = 0 THEN Fail("file not reopened", f) END
      END;
      f.mode := unused
    END
  END EnsureOpen;

  (* Puts f's stream at position, ready for what it is about to be used
     for. *)
  PROCEDURE PositionStream(f: File; position: LONGINT; use: INTEGER);
  BEGIN
    IF (f.mode # use) OR (f.position # position) THEN
      IF FSeek(f.stream, SYSTEM.VAL(SYSTEM.ADDRESS, position), seekSet) # 0 THEN Fail("seek failed", f) END;
      f.position := position;
      f.mode := use
    END
  END PositionStream;

  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File;
  BEGIN
    NEW(f);
    MakeAbsolute(name, f.registerName);
    f.workName[0] := 0X;
    RETURN f
  END New;

  (* Whether the stream can be read from at all - kept as a second guard
     after IsDirectory below, since a directory is not the only thing that
     opens but cannot be read. Leaves it at the start. *)
  PROCEDURE Readable(stream: SYSTEM.ADDRESS): BOOLEAN;
    VAR one: ARRAY 1 OF CHAR; count: SYSTEM.ADDRESS; ok: BOOLEAN;
  BEGIN
    ok := FSeek(stream, 0, seekSet) = 0;
    count := FRead(SYSTEM.ADR(one), 1, 1, stream);
    RETURN ok & ((count = 1) OR (FError(stream) = 0))
  END Readable;

  (* Whether path names a directory. On Linux and OpenBSD, fopen(path,
     "rb") of a directory succeeds but a one-byte fread of it fails
     (ferror set) - Readable above used to be the only guard, relying on
     that. Probed live on NetBSD 11.0/terhali (2026-09-20) after a real
     BSD-hardware run of llvm-files-extra caught check 14 failing there:
     NetBSD's fread happily returns a byte read out of a directory stream
     (count=1, ferror=0) - an old BSD read(2)-on-a-directory allowance
     Linux and OpenBSD's libc no longer honor - so Readable alone cannot
     tell a directory from an ordinary file there. opendir/closedir gave a
     platform-independent answer instead of relying on that fread quirk,
     until 2026-09-25, when they were replaced by access: NetBSD versions opendir
     (the real one is __opendir30, and the linker warns on every program
     that names plain opendir), which a fixed external name cannot follow.
     access(path + "/.", F_OK) succeeds only when path is a directory
     (resolving "." under anything else fails with ENOTDIR), is not
     versioned anywhere, and gave the same answers for a directory, a
     file, a missing path and /dev/null on Linux, OpenBSD, NetBSD and
     FreeBSD. *)
  PROCEDURE IsDirectory(VAR path: FileName): BOOLEAN;
    CONST existenceOnly = 0; (* F_OK, 0 on all four *)
    VAR withDot: ARRAY nameLength + 3 OF CHAR; i: LONGINT; (* path, "/.", 0X *)
  BEGIN
    i := 0;
    WHILE (i < LEN(path)) & (path[i] # 0X) DO withDot[i] := path[i]; INC(i) END;
    withDot[i] := "/"; withDot[i + 1] := "."; withDot[i + 2] := 0X;
    RETURN Access(SYSTEM.ADR(withDot), existenceOnly) = 0
  END IsDirectory;

  (* The file called name, or NIL if there is none or it cannot be opened.
     It is opened for reading and writing if the system allows, else for
     reading only. *)
  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File; path: FileName; stream, size: SYSTEM.ADDRESS; ignored: LONGINT;
  BEGIN
    f := NIL;
    IF (StringLength(name) > 0) & (StringLength(name) < nameLength) THEN
      MakeAbsolute(name, path);
      IF ~IsDirectory(path) THEN
        stream := OpenStream(path, "r+b");
        IF stream = 0 THEN stream := OpenStream(path, "rb") END;
        IF stream # 0 THEN
          size := -1;
          IF Readable(stream) & (FSeek(stream, 0, seekEnd) = 0) THEN size := FTell(stream) END;
          IF (size >= 0) & (size <= MAX(LONGINT)) THEN
            NEW(f);
            COPY(path, f.workName);
            f.stream := stream;
            f.created := TRUE;
            f.length := SYSTEM.VAL(LONGINT, size)
          ELSE
            ignored := FClose(stream)
          END
        END
      END
    END;
    RETURN f
  END Old;

  (* Writes out what is buffered and closes the stream; f can still be
     used, reopening itself. A New file that was never written to is
     created, empty. *)
  PROCEDURE Close*(f: File);
  BEGIN
    IF (f.stream # 0) OR ~f.created THEN
      EnsureOpen(f);
      IF FClose(f.stream) # 0 THEN Fail("error writing file", f) END;
      f.stream := 0
    END
  END Close;

  (* Closes f, and if it came from New gives it its name (replacing any
     file already there). *)
  PROCEDURE Register*(f: File);
  BEGIN
    Close(f);
    IF f.registerName[0] # 0X THEN
      IF CRename(SYSTEM.ADR(f.workName), SYSTEM.ADR(f.registerName)) # 0 THEN
        Fail("could not rename temporary file as its registered name", f)
      END;
      COPY(f.registerName, f.workName);
      f.registerName[0] := 0X
    END
  END Register;

  PROCEDURE Length*(f: File): LONGINT;
  BEGIN
    RETURN f.length
  END Length;

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

  PROCEDURE Pos*(VAR r: Rider): LONGINT;
  BEGIN
    RETURN r.position
  END Pos;

  PROCEDURE Base*(VAR r: Rider): File;
  BEGIN
    RETURN r.file
  END Base;

  (* The byte at r's position, and on to the next. At the end of the file x
     is 0X and r.eof is set. *)
  PROCEDURE Read*(VAR r: Rider; VAR x: CHAR);
    VAR f: File; one: ARRAY 1 OF CHAR; got: BOOLEAN;
  BEGIN
    f := r.file;
    got := FALSE;
    IF r.position < f.length THEN
      EnsureOpen(f);
      PositionStream(f, r.position, reading);
      IF FRead(SYSTEM.ADR(one), 1, 1, f.stream) = 1 THEN
        got := TRUE;
        INC(f.position); INC(r.position)
      ELSE
        f.mode := unused (* the file is shorter than we think *)
      END
    END;
    IF got THEN x := one[0]
    ELSE x := 0X; r.eof := TRUE
    END
  END Read;

  (* n bytes from address a, at r's position, extending the file as far as
     they go past the end *)
  PROCEDURE WriteBlock(VAR r: Rider; a, n: SYSTEM.ADDRESS);
    VAR f: File;
  BEGIN
    f := r.file;
    EnsureOpen(f);
    PositionStream(f, r.position, writing);
    IF FWrite(a, 1, n, f.stream) # n THEN Fail("error writing file", f) END;
    INC(f.position, SYSTEM.VAL(LONGINT, n));
    INC(r.position, SYSTEM.VAL(LONGINT, n));
    IF r.position > f.length THEN f.length := r.position END;
    r.res := 0
  END WriteBlock;

  PROCEDURE Write*(VAR r: Rider; x: CHAR);
    VAR one: ARRAY 1 OF CHAR;
  BEGIN
    one[0] := x;
    WriteBlock(r, SYSTEM.ADR(one), 1)
  END Write;

  (* The characters of x up to and including its 0X (all of x if it has
     none) - the terminator is written, as voc does, so that ReadString
     finds where the string ends. *)
  PROCEDURE WriteString*(VAR r: Rider; x: ARRAY OF CHAR);
    VAR n: LONGINT;
  BEGIN
    n := StringLength(x);
    IF n < LEN(x) THEN INC(n) END;
    WriteBlock(r, SYSTEM.ADR(x), SYSTEM.VAL(SYSTEM.ADDRESS, n))
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

  (* Deletes the file called name; res is 0 if it did, else not 0. *)
  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Unlink(name)
  END Delete;

  (* Renames the file old to new, replacing a file of that name; res is 0
     if it did, else not 0. *)
  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := -1;
    IF (StringLength(old) < LEN(old)) & (StringLength(new) < LEN(new)) THEN
      IF CRename(SYSTEM.ADR(old), SYSTEM.ADR(new)) = 0 THEN res := 0 END
    END
  END Rename;

END Files.
