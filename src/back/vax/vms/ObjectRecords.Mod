MODULE ObjectRecords;

  (* Where VaxObjectWriter's records go, for poc built for VMS (PLAN.md
     Phase 18 step 4; doc/developer/vax-object-language.md, sections 10,
     15.3 and 15.9): an object, each record one RMS record, written by
     rtl/vax's RecordFiles. tools/bootstrap/vax-v1 builds poc for VMS with
     this directory on its import path, and src/back/vax/host has the same
     interface for poc built elsewhere. *)

  IMPORT RecordFiles;

  TYPE
    File* = RecordFiles.File;

  (* A new file called name, for records of at most maximum bytes: NIL if
     it cannot be made *)
  PROCEDURE Open*(name: ARRAY OF CHAR; maximum: INTEGER): File;
  BEGIN
    RETURN RecordFiles.Create(name, maximum)
  END Open;

  (* A record, the first length bytes of bytes *)
  PROCEDURE Put*(f: File; VAR bytes: ARRAY OF CHAR; length: INTEGER);
  BEGIN
    RecordFiles.Put(f, bytes, length)
  END Put;

  PROCEDURE Close*(f: File);
  BEGIN
    RecordFiles.Close(f)
  END Close;

  (* The source file name, for the debugger records (poc -g;
     doc/developer/vax-object-language.md, section 16.6): its name and its
     RMS attributes, the creation time (8 bytes), end-of-file block, first
     free byte and record format: its resultant name and its own, which
     spare the debugger's note that the file it opens may not be the one
     compiled; the name as given and zeros if it cannot be opened *)
  PROCEDURE SourceAttributes*(name: ARRAY OF CHAR; VAR vmsName, created: ARRAY OF CHAR;
                              VAR endBlock, firstFree, format: LONGINT);
    VAR i: INTEGER;
  BEGIN
    IF ~RecordFiles.Describe(name, vmsName, created, endBlock, firstFree, format) THEN
      COPY(name, vmsName);
      FOR i := 0 TO 7 DO created[i] := 0X END;
      endBlock := 0; firstFree := 0; format := 0
    END
  END SourceAttributes;

END ObjectRecords.
