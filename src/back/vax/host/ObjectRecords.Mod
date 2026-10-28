MODULE ObjectRecords;

  (* Where VaxObjectWriter's records go, for poc built for Linux and the
     BSDs, and Stage 0 under voc (PLAN.md Phase 18 step 4;
     doc/developer/vax-object-language.md, sections 10 and 15.3): a file
     in the form VMS keeps a file of variable-length records on disk, each
     record a 2-byte count, least significant byte first, its bytes, and a
     pad byte when the count is odd. On the guest, tools/objconvert turns
     such a file, sent by FTP in binary mode, into an object.
     src/back/vax/vms has the same interface for poc built for VMS, which
     tools/bootstrap/vax-v1 builds with that directory on its import path
     instead of this one. *)

  IMPORT Files;

  TYPE
    File* = POINTER TO FileDesc;
    FileDesc = RECORD
      file: Files.File;
      rider: Files.Rider;
      writing: BOOLEAN (* made by Create, not opened by Open *)
    END;

  (* A new file called name, for records of at most maximum bytes (which
     the VMS implementation needs): NIL if it cannot be made *)
  PROCEDURE Create*(name: ARRAY OF CHAR; maximum: INTEGER): File;
    VAR f: File; file: Files.File;
  BEGIN
    file := Files.New(name);
    IF file = NIL THEN RETURN NIL END;
    NEW(f); f.file := file; Files.Set(f.rider, file, 0); f.writing := TRUE;
    RETURN f
  END Create;

  (* The file called name, to read its records with Get (an object named on
     poc -library's command line: doc/developer/vax-macro32-backend.md,
     section 13.1, proposal 6), one IsCounted takes: NIL if it cannot be
     opened *)
  PROCEDURE Open*(name: ARRAY OF CHAR): File;
    VAR f: File; file: Files.File;
  BEGIN
    file := Files.Old(name);
    IF file = NIL THEN RETURN NIL END;
    NEW(f); f.file := file; Files.Set(f.rider, file, 0); f.writing := FALSE;
    RETURN f
  END Open;

  (* The next record, in bytes, its length in length, as many of its bytes
     as bytes holds: FALSE at the file's end, or a count of 0, the zeros
     after the last record *)
  PROCEDURE Get*(f: File; VAR bytes: ARRAY OF CHAR; VAR length: INTEGER): BOOLEAN;
    VAR low, high, ch: CHAR; count, i: LONGINT;
  BEGIN
    Files.Read(f.rider, low); Files.Read(f.rider, high);
    IF f.rider.eof THEN RETURN FALSE END;
    count := ORD(low) + 256 * LONG(ORD(high));
    IF count = 0 THEN RETURN FALSE END;
    length := 0;
    FOR i := 1 TO count DO
      Files.Read(f.rider, ch);
      IF length < LEN(bytes) THEN bytes[length] := ch; INC(length) END
    END;
    IF ODD(count) THEN Files.Read(f.rider, ch) END;
    RETURN TRUE
  END Get;

  (* A record, the first length bytes of bytes *)
  PROCEDURE Put*(f: File; VAR bytes: ARRAY OF CHAR; length: INTEGER);
    VAR i: INTEGER;
  BEGIN
    Files.Write(f.rider, CHR(length MOD 256)); Files.Write(f.rider, CHR(length DIV 256));
    FOR i := 0 TO length - 1 DO Files.Write(f.rider, bytes[i]) END;
    IF ODD(length) THEN Files.Write(f.rider, 0X) END
  END Put;

  PROCEDURE Close*(f: File);
  BEGIN
    IF f.writing THEN Files.Register(f.file) END;
    Files.Close(f.file)
  END Close;

  (* The file at from, written by Put, copied byte for byte to to (a
     library's installed: PLAN.md Phase 18 step 6;
     doc/developer/vax-object-language.md, section 17.4): FALSE if either
     cannot be opened *)
  PROCEDURE Copy*(from, to: ARRAY OF CHAR): BOOLEAN;
    VAR f, g: Files.File; r, w: Files.Rider; ch: CHAR;
  BEGIN
    f := Files.Old(from);
    IF f = NIL THEN RETURN FALSE END;
    g := Files.New(to);
    IF g = NIL THEN Files.Close(f); RETURN FALSE END;
    Files.Set(r, f, 0); Files.Set(w, g, 0);
    Files.Read(r, ch);
    WHILE ~r.eof DO Files.Write(w, ch); Files.Read(r, ch) END;
    Files.Close(f);
    Files.Register(g); Files.Close(g);
    RETURN TRUE
  END Copy;

  (* Whether the file called name is an object in the form Put writes, as
     poc takes one named on the command line (doc/developer/
     vax-macro32-backend.md, section 13.1): its counts walk exactly to its
     end, none above 512, the object language's longest record and the
     most OBJCONVERT takes, and each record's first byte is an object
     record's type, OBJ$C_HDR (0) to OBJ$C_EOMW (7), but that a count of
     0 followed only by zero bytes ends it, as OBJCONVERT -COUNTED pads its
     last block (section 13.2, proposal 4). An object fetched from VMS by
     FTP in binary is not: its records arrive run together, with no
     counts. *)
  PROCEDURE IsCounted*(name: ARRAY OF CHAR): BOOLEAN;
    VAR f: Files.File; r: Files.Rider; low, high, type: CHAR; length, position, size: LONGINT; ok: BOOLEAN;
  BEGIN
    f := Files.Old(name);
    IF f = NIL THEN RETURN FALSE END;
    size := Files.Length(f); position := 0; ok := size > 0;
    WHILE ok & (position < size) DO
      IF position + 2 > size THEN
        ok := FALSE
      ELSE
        Files.Set(r, f, position); Files.Read(r, low); Files.Read(r, high);
        length := ORD(low) + 256 * LONG(ORD(high));
        IF (length = 0) & (position > 0) THEN (* the end: zeros to the file's *)
          position := position + 2;
          WHILE ok & (position < size) DO Files.Read(r, type); ok := type = 0X; INC(position) END
        ELSIF position + 3 > size THEN
          ok := FALSE
        ELSE
          Files.Read(r, type);
          position := position + 2 + length + length MOD 2;
          ok := (length > 0) & (length <= 512) & (ORD(type) <= 7) & (position <= size)
        END
      END
    END;
    Files.Close(f);
    RETURN ok
  END IsCounted;

  (* The source file name, for the debugger records (poc -g;
     doc/developer/vax-object-language.md, section 16.6): its name for VMS,
     its last part, since a path of this system's means nothing there, and
     its RMS attributes, the creation time (8 bytes), end-of-file block,
     first free byte and record format, zeros, since it has none here *)
  PROCEDURE SourceAttributes*(name: ARRAY OF CHAR; VAR vmsName, created: ARRAY OF CHAR;
                              VAR endBlock, firstFree, format: LONGINT);
    VAR i, from: INTEGER;
  BEGIN
    i := 0; from := 0;
    WHILE (i < LEN(name)) & (name[i] # 0X) DO
      IF name[i] = "/" THEN from := i + 1 END;
      INC(i)
    END;
    i := 0;
    WHILE (from < LEN(name)) & (name[from] # 0X) & (i < LEN(vmsName) - 1) DO
      vmsName[i] := name[from]; INC(i); INC(from)
    END;
    vmsName[i] := 0X;
    FOR i := 0 TO 7 DO created[i] := 0X END;
    endBlock := 0; firstFree := 0; format := 0
  END SourceAttributes;

END ObjectRecords.
