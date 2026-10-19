MODULE ObjectRecords;

  (* Where VaxObjectWriter's records go, for poc built for VMS (PLAN.md
     Phase 18 step 4; doc/developer/vax-object-language.md, sections 10
     and 15.3), which tools/bootstrap/vax-v1 builds with this directory on
     its import path, and src/back/vax/host has the same interface for poc
     built elsewhere. Until step 4c gives it rtl/vax's RecordFiles, which
     writes an RMS record at a time, it writes the host's form, the
     records counted in a stream of bytes, through Files, so that poc for
     VMS builds; poc on VMS writes no object before then. *)

  IMPORT Files;

  TYPE
    File* = POINTER TO FileDesc;
    FileDesc = RECORD
      file: Files.File;
      rider: Files.Rider
    END;

  (* A new file called name, for records of at most maximum bytes: NIL if
     it cannot be made *)
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
