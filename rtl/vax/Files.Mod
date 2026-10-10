MODULE Files;

  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 2): rtl/llvm/Files.Mod's interface, as far as poc's own
     source uses it - File and Rider, Old, New, Register, Close, Length,
     Set, Base, Read, Write, ReadString, ReadLine, WriteString and Delete -
     for VAX/VMS, over RMS through the routines in rtl/vax/PocRtl.mar.

     THE MODEL is rtl/llvm's: a File is a byte sequence with a length, a
     Rider a position in one and the result of the last operation.

     A FILE POC MAKES is Stream_LF, with carriage return carriage control,
     written and read by block I/O ($WRITE, $READ), so that every byte
     comes back as it was written and MACRO, LINK and TYPE read it as text.
     A File keeps one 512-byte block of it; RMS keeps the file's end at
     the highest byte written. New makes nothing on disk. The first block
     written out (or Close, or Register) creates the file under a name of
     its own, in the directory of the name given to New, and Register
     renames it that name, as a new version: a compiler that stops half
     way leaves the files it had. A File is written only before it is
     closed, and a file Old opens is never written: either is an error.

     A FILE OLD OPENS of another record format - variable-length or VFC,
     as FTP in ASCII mode and the editors write, Stream or Stream_CR - is
     read a record at a time ($GET), an LF (0AX) after each, so that a
     source written on VMS reads as it does on Unix. Old reads it through
     once to count its bytes, LFs included, for Length. A Stream_LF,
     fixed-length or undefined file is read as its bytes, its length from
     the end-of-file block and the first free byte in it.

     A name is given to RMS as it is: case does not matter, and a missing
     version means the highest. An error that cannot be reported to the
     caller - a file that cannot be created or written - stops the
     program with a message and HALT(99), as rtl/llvm's does. *)

  IMPORT SYSTEM;

  CONST
    blockSize = 512;
    nameLength = 256; (* a name and its 0X, as RMS takes at most 255 *)
    controlSize = 768; (* PocRtl.mar's POC_F_SIZE, which it checks *)
    recordSize = 32767; (* the longest record RMS reads *)

  TYPE
    Name = ARRAY nameLength OF CHAR;
    (* the file's FAB, RAB, NAM block and XABFHC, and its resultant name *)
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
      isNew: BOOLEAN; (* from New and not registered yet *)
      created: BOOLEAN; (* a New file's file is on disk *)
      open: BOOLEAN; (* the control's file is open *)
      closed: BOOLEAN; (* Close or Register has been called *)
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

  PROCEDURE ["VMS"] POC_FILE_OPEN(VAR control: Control; VAR name: Name; length: SYSTEM.INT32;
                                  VAR info: Info): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_REOPEN(VAR control: Control; VAR info: Info): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_CREATE(VAR control: Control; VAR name: Name; length: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_READ(VAR control: Control; VAR position: LONGINT; VAR block: Block): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_WRITE(VAR control: Control; VAR position: LONGINT; VAR block: Block;
                                   count: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_GET(VAR control: Control; VAR record: Record; size: SYSTEM.INT32): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_REWIND(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_CLOSE(VAR control: Control): INTEGER;
  PROCEDURE ["VMS"] POC_FILE_RENAME(VAR control: Control; VAR name: Name; length: SYSTEM.INT32): INTEGER;
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
      IF ~ODD(POC_FILE_CREATE(f.control, f.name, Length0X(f.name))) THEN Fail("file not created", f) END;
      f.created := TRUE; f.open := TRUE
    END
  END Create;

  (* The control's file open again, to be read, after Close. *)
  PROCEDURE Reopen(f: File);
    VAR info: Info;
  BEGIN
    IF ~f.open THEN
      IF ~ODD(POC_FILE_REOPEN(f.control, info)) THEN Fail("file not reopened", f) END;
      f.open := TRUE
    END
  END Reopen;

  (* The bytes of f's block not written out written to its file. *)
  PROCEDURE Flush(f: File);
    VAR count: LONGINT;
  BEGIN
    IF f.dirty THEN
      Create(f);
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
        Reopen(f);
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
    Reopen(f);
    IF position < f.recordStart THEN Rewind(f) END;
    WHILE position >= f.recordStart + f.recordLength DO
      IF ~NextRecord(f) THEN Fail("error reading file", f) END
    END;
    IF position - f.recordStart < f.recordLength - 1 THEN x := f.record[position - f.recordStart]
    ELSE x := 0AX
    END
  END RecordByte;

  PROCEDURE NewFile(VAR name: Name): File;
    VAR f: File;
  BEGIN
    NEW(f);
    COPY(name, f.name);
    f.blockStart := -1;
    RETURN f
  END NewFile;

  (* A new, empty file, to be called name once registered; nothing is made
     on disk until it is written to, closed or registered. *)
  PROCEDURE New*(name: ARRAY OF CHAR): File;
    VAR f: File; s: Name; n: INTEGER;
  BEGIN
    IF ~CopyName(name, s, n) THEN Fail("file name too long", NIL) END;
    f := NewFile(s);
    f.isNew := TRUE;
    RETURN f
  END New;

  (* The file called name, opened to be read, or NIL if there is none or it
     cannot be read. *)
  PROCEDURE Old*(name: ARRAY OF CHAR): File;
    VAR f: File; s: Name; n: INTEGER; info: Info; block: LONGINT;
  BEGIN
    IF ~CopyName(name, s, n) THEN RETURN NIL END;
    f := NewFile(s);
    IF ~ODD(POC_FILE_OPEN(f.control, f.name, n, info)) THEN RETURN NIL END;
    f.open := TRUE;
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
  END Old;

  (* Writes out what is buffered and closes the file; f can still be read,
     opening it again. A New file that was never written to is made,
     empty. *)
  PROCEDURE Close*(f: File);
  BEGIN
    IF f.isNew THEN Create(f); Flush(f) END;
    IF f.open THEN
      IF ~ODD(POC_FILE_CLOSE(f.control)) THEN Fail("error writing file", f) END;
      f.open := FALSE
    END;
    f.closed := TRUE
  END Close;

  (* Closes f, and if it came from New gives it its name, as a new
     version. *)
  PROCEDURE Register*(f: File);
  BEGIN
    Close(f);
    IF f.isNew THEN
      IF ~ODD(POC_FILE_RENAME(f.control, f.name, Length0X(f.name))) THEN
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
     extending the file, and on to the next. *)
  PROCEDURE Write*(VAR r: Rider; x: SYSTEM.BYTE);
    VAR f: File;
  BEGIN
    f := r.file;
    IF ~f.isNew OR f.closed THEN Fail("file not open to be written", f) END;
    Load(f, r.position);
    f.block[r.position - f.blockStart] := x;
    f.dirty := TRUE;
    INC(r.position);
    IF r.position > f.length THEN f.length := r.position END;
    r.res := 0
  END Write;

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
     res is 0 if it did, else 2 for a name too long, or RMS's status (its
     low word under -O2), as Platform.Unlink. *)
  PROCEDURE Delete*(name: ARRAY OF CHAR; VAR res: INTEGER);
    VAR s: Name; n: INTEGER;
  BEGIN
    IF ~CopyName(name, s, n) THEN res := 2
    ELSE
      res := POC_ERASE(s, n);
      IF ODD(res) THEN res := 0 END
    END
  END Delete;

END Files.
