MODULE Files;

  (* PLAN.md Phase 10 step 3 and Phase 12 step 5d: Oberon files - the
     Oakwood Guidelines' Files module with voc's interface (src/runtime/
     Files.Mod): File and Rider, New, Old, Register, Close, Purge, Length,
     GetDate, GetName, Set, Pos, Base, Read, ReadByte, ReadBytes, Write,
     WriteBytes, the typed riders (Read/Write Bool, Int, LInt, Set, Real,
     LReal, String, Num, and ReadLine), Delete, Rename, ChangeDirectory,
     SetSearchPath, MaxNameLength and MaxPathLength. Read, Write and
     ReadByte take a SYSTEM.BYTE, so a CHAR, a BOOLEAN or a one-byte
     SHORTINT variable can be read into (AGENTS.md, "SYSTEM subset").

     THE EXTERNAL FORMAT of the typed riders is Oakwood's (1.2.5.4), under
     both size models: little-endian, an INTEGER 2 bytes, a LONGINT 4, a
     SET 4 (element 0 the least significant bit), a BOOLEAN 1 (0 or 1), a
     REAL and a LONGREAL their IEEE 4 and 8 bytes, a string up to its 0X
     and the 0X. So a file written under -O2 reads back under -OC and with
     voc. Under -OC an INTEGER or a LONGINT wider than its format loses
     its high bytes on the way out, as voc's does; a value read back is
     sign-extended, where voc's -OC reads a negative one as a large
     positive one (decided with the user 2026-10-02). WriteNum and
     ReadNum are voc's variable-length numbers: seven bits a byte, the
     last byte's top bit clear and its bit 6 the sign.

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
     meant to.

     OPEN STREAMS AND FINALIZATION. Close writes everything out and closes
     the stream, but the File stays usable: the next operation reopens it.
     Every File is registered with the collector (GarbageCollectedHeap.
     RegisterFinalizer, Phase 12 step 5c), as voc's are: when one is no
     longer reachable, or the program ends, its stream is closed, its data
     written, and the temporary file of a New file never registered is
     deleted.

     OLD AND THE SEARCH PATH. A name with a "/" in it is looked for where
     it says. Any other is looked for in each directory of the search path
     in turn, which is just the current directory until SetSearchPath
     sets one: directories separated by ";", blanks around them ignored, a
     leading "~" standing for $HOME, as voc's.

     Where this differs from voc's, besides the missing procedures:
     - GetName gives the name as given to Old or New, or the temporary
       file's, as voc's, but the temporary file's is an absolute path;
     - two Old calls for one file give two independent Files (voc shares
       one, so a write through one is at once visible through the other);
       after a Register over a file that another File has open, that File
       keeps reading the old contents;
     - ReadString and ReadLine cut a value too long for the array short
       (and ReadLine skips the rest of the line) where voc overruns it;
     - an error that cannot be reported to the caller - a file that cannot
       be created, a failed write - stops the program with a message and
       Halt(99), as voc does, but the message goes to standard error, where
       voc's goes to standard output (Phase 11 D12);
     - the C `int` results below are declared LONGINT, right under the -O2
       size model only (see Platform.Mod). *)

  IMPORT SYSTEM, Platform, FileDescriptorOutput, GarbageCollectedHeap;

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
      name: FileName; (* as given to Old or New, for GetName *)
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
    MaxPathLength-, MaxNameLength-: INTEGER;
    temporaryCount: LONGINT;
    searchPath: POINTER TO ARRAY OF CHAR; (* NIL: the current directory *)
    home: FileName;

  PROCEDURE ["C", "fopen"] FOpen(path, mode: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "fclose"] FClose(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "fflush"] FFlush(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "fread"] FRead(buffer, size, count, stream: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "fwrite"] FWrite(buffer, size, count, stream: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "fseek"] FSeek(stream, offset: SYSTEM.ADDRESS; whence: SYSTEM.INT32): SYSTEM.INT32;
  PROCEDURE ["C", "ferror"] FError(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "ftell"] FTell(stream: SYSTEM.ADDRESS): SYSTEM.ADDRESS;
  PROCEDURE ["C", "rename"] CRename(old, new: SYSTEM.ADDRESS): SYSTEM.INT32;
  PROCEDURE ["C", "fileno"] FileNumber(stream: SYSTEM.ADDRESS): SYSTEM.INT32;
  (* Directory detection for Old (see IsDirectory's own comment). *)
  PROCEDURE ["C", "access"] Access(path: SYSTEM.ADDRESS; mode: SYSTEM.INT32): SYSTEM.INT32;

  (* text on standard error, up to its 0X *)
  PROCEDURE Say(text: ARRAY OF CHAR);
    VAR length: LONGINT;
  BEGIN
    length := 0;
    WHILE (length < LEN(text)) & (text[length] # 0X) DO INC(length) END;
    FileDescriptorOutput.Write(FileDescriptorOutput.standardError, SYSTEM.ADR(text),
                               SYSTEM.VAL(SYSTEM.ADDRESS, length))
  END Say;

  PROCEDURE SayLn;
    VAR one: ARRAY 1 OF CHAR;
  BEGIN
    one[0] := 0AX;
    FileDescriptorOutput.Write(FileDescriptorOutput.standardError, SYSTEM.ADR(one), 1)
  END SayLn;

  (* An error nothing above can be told about: says what and where, on
     standard error (Phase 11 D12; voc's Files writes it to standard
     output), and stops the program. *)
  PROCEDURE Fail(message: ARRAY OF CHAR; f: File);
  BEGIN
    SayLn; Say("-- "); Say(message);
    IF f # NIL THEN
      Say(": ");
      IF f.registerName[0] # 0X THEN Say(f.registerName)
      ELSE Say(f.workName)
      END
    END;
    SayLn;
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

  (* The collector's finalizer of a File (OPEN STREAMS AND FINALIZATION
     above) *)
  PROCEDURE Finalize(obj: SYSTEM.PTR);
    VAR f: File; ignored: SYSTEM.INT32; res: INTEGER;
  BEGIN
    f := SYSTEM.VAL(File, obj);
    IF f.stream # 0 THEN ignored := FClose(f.stream); f.stream := 0 END;
    IF f.created & (f.registerName[0] # 0X) THEN res := Platform.Unlink(f.workName) END
  END Finalize;

  PROCEDURE NewFile(VAR name: ARRAY OF CHAR): File;
    VAR f: File;
  BEGIN
    NEW(f);
    COPY(name, f.name);
    GarbageCollectedHeap.RegisterFinalizer(f, Finalize);
    RETURN f
  END NewFile;

  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File;
  BEGIN
    IF StringLength(name) >= nameLength THEN Fail("file name too long", NIL) END;
    f := NewFile(name);
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

  (* The file at path (absolute), opened, or NIL; name is the name it was
     asked for by. *)
  PROCEDURE OpenOld(VAR path: FileName; VAR name: ARRAY OF CHAR): File;
    VAR f: File; stream, size: SYSTEM.ADDRESS; ignored: LONGINT;
  BEGIN
    f := NIL;
    IF ~IsDirectory(path) THEN
      stream := OpenStream(path, "r+b");
      IF stream = 0 THEN stream := OpenStream(path, "rb") END;
      IF stream # 0 THEN
        size := -1;
        IF Readable(stream) & (FSeek(stream, 0, seekEnd) = 0) THEN size := FTell(stream) END;
        IF (size >= 0) & (size <= MAX(LONGINT)) THEN
          f := NewFile(name);
          COPY(path, f.workName);
          f.stream := stream;
          f.created := TRUE;
          f.length := SYSTEM.VAL(LONGINT, size)
        ELSE
          ignored := FClose(stream)
        END
      END
    END;
    RETURN f
  END OpenOld;

  (* The next directory of the search path from position, in dir ("" when
     there are no more), as voc's ScanPath *)
  PROCEDURE NextDirectory(VAR position: LONGINT; VAR dir: FileName);
    VAR i: LONGINT; ch: CHAR;
  BEGIN
    i := 0;
    ch := searchPath[position];
    WHILE (ch = " ") OR (ch = ";") DO INC(position); ch := searchPath[position] END;
    IF ch = "~" THEN
      INC(position); ch := searchPath[position];
      WHILE (home[i] # 0X) & (i < nameLength - 1) DO dir[i] := home[i]; INC(i) END
    END;
    WHILE (ch # 0X) & (ch # ";") DO
      IF i < nameLength - 1 THEN dir[i] := ch; INC(i) END;
      INC(position); ch := searchPath[position]
    END;
    WHILE (i > 0) & (dir[i - 1] = " ") DO DEC(i) END;
    dir[i] := 0X
  END NextDirectory;

  (* path := dir/name, made absolute; FALSE if it would not fit *)
  PROCEDURE JoinPath(VAR dir: FileName; VAR name: ARRAY OF CHAR; VAR path: FileName): BOOLEAN;
    VAR joined: ARRAY 2 * nameLength OF CHAR; i, k, n: LONGINT;
  BEGIN
    i := StringLength(dir);
    WHILE (i > 0) & (dir[i - 1] = "/") DO DEC(i) END;
    n := StringLength(name);
    IF i + 1 + n + StringLength(Platform.CWD) + 1 >= nameLength THEN RETURN FALSE END;
    FOR k := 0 TO i - 1 DO joined[k] := dir[k] END;
    IF (i > 0) OR (dir[0] = "/") THEN joined[i] := "/"; INC(i) END;
    FOR k := 0 TO n - 1 DO joined[i + k] := name[k] END;
    joined[i + n] := 0X;
    MakeAbsolute(joined, path);
    RETURN TRUE
  END JoinPath;

  PROCEDURE HasDirectory(VAR name: ARRAY OF CHAR): BOOLEAN;
    VAR i: LONGINT;
  BEGIN
    i := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) & (name[i] # "/") DO INC(i) END;
    RETURN (i < LEN(name)) & (name[i] = "/")
  END HasDirectory;

  (* The file called name, or NIL if there is none or it cannot be opened
     (OLD AND THE SEARCH PATH above). It is opened for reading and writing
     if the system allows, else for reading only. *)
  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File; path, dir: FileName; position: LONGINT;
  BEGIN
    f := NIL;
    IF (StringLength(name) > 0) & (StringLength(name) < nameLength) THEN
      IF HasDirectory(name) OR (searchPath = NIL) THEN
        MakeAbsolute(name, path);
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

  (* Empties f: its length is 0. *)
  PROCEDURE Purge*(f: File);
    VAR res: INTEGER;
  BEGIN
    IF f.created THEN
      EnsureOpen(f);
      IF FFlush(f.stream) # 0 THEN Fail("error writing file", f) END;
      res := Platform.Truncate(FileNumber(f.stream), 0);
      IF res # 0 THEN Fail("file not truncated", f) END;
      f.mode := unused
    END;
    f.length := 0
  END Purge;

  (* The time and date f was last changed, in Oberon's clock format
     (Platform.GetClock): t = hour * 4096 + minute * 64 + second, d =
     year MOD 100 * 512 + month * 32 + day, month 1..12. A New file not yet written to
     is created first, as voc's. *)
  PROCEDURE GetDate*(f: File; VAR t, d: LONGINT);
    VAR identity: Platform.FileIdentity; res: INTEGER;
  BEGIN
    EnsureOpen(f);
    IF FFlush(f.stream) # 0 THEN Fail("error writing file", f) END;
    res := Platform.Identify(FileNumber(f.stream), identity);
    IF res # 0 THEN Fail("file not identified", f) END;
    Platform.MTimeAsClock(identity, t, d)
  END GetDate;

  (* The name f was asked for by (Old) or registered under (New and
     Register); a New file not registered yet: its temporary file, "" if
     it has none yet. *)
  PROCEDURE GetName*(f: File; VAR name: ARRAY OF CHAR);
  BEGIN
    IF f.registerName[0] # 0X THEN COPY(f.workName, name) ELSE COPY(f.name, name) END
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
  PROCEDURE Read*(VAR r: Rider; VAR x: SYSTEM.BYTE);
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

  PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
  BEGIN
    WriteBlock(r, SYSTEM.ADR(x), 1)
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
    VAR f: File; available, got: LONGINT; outside: SYSTEM.BYTE;
  BEGIN
    IF n > LEN(x) THEN outside := x[n - 1] END;
    got := 0;
    IF n > 0 THEN
      f := r.file;
      available := f.length - r.position;
      IF available > n THEN available := n END;
      IF available > 0 THEN
        EnsureOpen(f);
        PositionStream(f, r.position, reading);
        got := SYSTEM.VAL(LONGINT, FRead(SYSTEM.ADR(x), 1, SYSTEM.VAL(SYSTEM.ADDRESS, available), f.stream));
        INC(f.position, got); INC(r.position, got);
        IF got < available THEN f.mode := unused END
      END
    ELSE
      n := 0
    END;
    r.res := n - got;
    r.eof := r.res > 0
  END ReadBytes;

  (* The first n bytes of x; n larger than x traps, as in ReadBytes. *)
  PROCEDURE WriteBytes*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE; n: LONGINT);
    VAR outside: SYSTEM.BYTE;
  BEGIN
    IF n > LEN(x) THEN outside := x[n - 1] END;
    IF n > 0 THEN WriteBlock(r, SYSTEM.ADR(x), SYSTEM.VAL(SYSTEM.ADDRESS, n)) END;
    r.res := 0
  END WriteBytes;

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

  (* Deletes the file called name; res is 0 if it did, else the error
     code (Platform.ErrorCode). *)
  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Unlink(name)
  END Delete;

  (* Renames the file old to new, replacing a file of that name; res is 0
     if it did, else the error code (Platform.ErrorCode). *)
  PROCEDURE Rename*(old, new: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Rename(old, new)
  END Rename;

  (* Makes path the current directory; res is 0 if it did, else the error
     code. A relative name given to Old or New after it is taken from
     there. *)
  PROCEDURE ChangeDirectory*(path: ARRAY OF CHAR; VAR res: INTEGER);
  BEGIN
    res := Platform.Chdir(path)
  END ChangeDirectory;

  (* The directories Old looks in for a name without a "/" (OLD AND THE
     SEARCH PATH above); "" for just the current directory again. *)
  PROCEDURE SetSearchPath*(path: ARRAY OF CHAR);
    VAR n: LONGINT;
  BEGIN
    n := StringLength(path);
    IF n = 0 THEN searchPath := NIL
    ELSE NEW(searchPath, n + 1); COPY(path, searchPath^)
    END
  END SetSearchPath;

  (* ---- the typed riders (THE EXTERNAL FORMAT above) ---- *)

  (* the bytes of x, as they are in memory, in little-endian order *)
  PROCEDURE ToLittleEndian(VAR x: ARRAY OF SYSTEM.BYTE; VAR bytes: ARRAY OF CHAR);
    VAR i, n: LONGINT;
  BEGIN
    n := LEN(x);
    FOR i := 0 TO n - 1 DO
      IF Platform.LittleEndian THEN SYSTEM.GET(SYSTEM.ADR(x) + i, bytes[i])
      ELSE SYSTEM.GET(SYSTEM.ADR(x) + n - 1 - i, bytes[i])
      END
    END
  END ToLittleEndian;

  PROCEDURE FromLittleEndian(VAR bytes: ARRAY OF CHAR; VAR x: ARRAY OF SYSTEM.BYTE);
    VAR i, n: LONGINT;
  BEGIN
    n := LEN(x);
    FOR i := 0 TO n - 1 DO
      IF Platform.LittleEndian THEN SYSTEM.PUT(SYSTEM.ADR(x) + i, bytes[i])
      ELSE SYSTEM.PUT(SYSTEM.ADR(x) + n - 1 - i, bytes[i])
      END
    END
  END FromLittleEndian;

  (* A byte as a signed number, -128..127 *)
  PROCEDURE Signed(ch: CHAR): INTEGER;
  BEGIN
    IF ORD(ch) >= 128 THEN RETURN ORD(ch) - 256 ELSE RETURN ORD(ch) END
  END Signed;

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
    VAR b: ARRAY 4 OF CHAR;
  BEGIN
    ReadBytes(r, b, 4); FromLittleEndian(b, x)
  END ReadReal;

  PROCEDURE ReadLReal*(VAR r: Rider; VAR x: LONGREAL);
    VAR b: ARRAY 8 OF CHAR;
  BEGIN
    ReadBytes(r, b, 8); FromLittleEndian(b, x)
  END ReadLReal;

  (* A number WriteNum wrote, into x, which may be any integer variable of
     at most 8 bytes: its low bytes, as voc's. *)
  PROCEDURE ReadNum*(VAR r: Rider; VAR x: ARRAY OF SYSTEM.BYTE);
    VAR ch: CHAR; shift: INTEGER; q, part: SYSTEM.INT64; bytes: ARRAY 8 OF CHAR; i: LONGINT;
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
    ToLittleEndian(q, bytes);
    FOR i := 0 TO LEN(x) - 1 DO
      IF Platform.LittleEndian THEN SYSTEM.PUT(SYSTEM.ADR(x) + i, bytes[i])
      ELSE SYSTEM.PUT(SYSTEM.ADR(x) + LEN(x) - 1 - i, bytes[i])
      END
    END
  END ReadNum;

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
    VAR b: ARRAY 4 OF CHAR;
  BEGIN
    ToLittleEndian(x, b); WriteBytes(r, b, 4)
  END WriteReal;

  PROCEDURE WriteLReal*(VAR r: Rider; x: LONGREAL);
    VAR b: ARRAY 8 OF CHAR;
  BEGIN
    ToLittleEndian(x, b); WriteBytes(r, b, 8)
  END WriteLReal;

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
  Platform.GetEnv("HOME", home)
END Files.
