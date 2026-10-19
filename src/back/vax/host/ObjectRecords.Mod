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
      rider: Files.Rider
    END;

  (* A new file called name, for records of at most maximum bytes (which
     the VMS implementation needs): NIL if it cannot be made *)
  PROCEDURE Open*(name: ARRAY OF CHAR; maximum: INTEGER): File;
    VAR f: File; file: Files.File;
  BEGIN
    file := Files.New(name);
    IF file = NIL THEN RETURN NIL END;
    NEW(f); f.file := file; Files.Set(f.rider, file, 0);
    RETURN f
  END Open;

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
    Files.Register(f.file); Files.Close(f.file)
  END Close;

END ObjectRecords.
