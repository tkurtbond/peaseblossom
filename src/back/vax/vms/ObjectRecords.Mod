MODULE ObjectRecords;

  (* Where VaxObjectWriter's records go, for poc built for VMS (PLAN.md
     Phase 18 step 4; doc/developer/vax-object-language.md, sections 10,
     15.3 and 15.9): an object, each record one RMS record, written by
     rtl/vax's RecordFiles. tools/bootstrap/vax-v1 builds poc for VMS with
     this directory on its import path, and src/back/vax/host has the same
     interface for poc built elsewhere. *)

  IMPORT RecordFiles, Platform;

  TYPE
    File* = RecordFiles.File;

  (* A new file called name, for records of at most maximum bytes: NIL if
     it cannot be made *)
  PROCEDURE Create*(name: ARRAY OF CHAR; maximum: INTEGER): File;
  BEGIN
    RETURN RecordFiles.Create(name, maximum)
  END Create;

  (* The object called name, to read its records with Get (one named on poc
     -library's command line: doc/developer/vax-macro32-backend.md, section
     13.1, proposal 6): NIL if it cannot be opened, or is not a file of
     records *)
  PROCEDURE Open*(name: ARRAY OF CHAR): File;
  BEGIN
    RETURN RecordFiles.Open(name)
  END Open;

  (* The next record, in bytes, its length in length: FALSE at the file's
     end. One longer than bytes stops the program (RecordFiles.Get). *)
  PROCEDURE Get*(f: File; VAR bytes: ARRAY OF CHAR; VAR length: INTEGER): BOOLEAN;
  BEGIN
    RETURN RecordFiles.Get(f, bytes, length)
  END Get;

  (* A record, the first length bytes of bytes *)
  PROCEDURE Put*(f: File; VAR bytes: ARRAY OF CHAR; length: INTEGER);
  BEGIN
    RecordFiles.Put(f, bytes, length)
  END Put;

  PROCEDURE Close*(f: File);
  BEGIN
    RecordFiles.Close(f)
  END Close;

  (* The object at from copied to to, its records and attributes whole, by
     DCL's COPY (a library's installed: PLAN.md Phase 18 step 6;
     doc/developer/vax-object-language.md, section 17.4): FALSE if it
     could not be *)
  PROCEDURE Copy*(from, to: ARRAY OF CHAR): BOOLEAN;
    VAR command: ARRAY 2 * 1024 + 8 OF CHAR; i: INTEGER;

    PROCEDURE Add(s: ARRAY OF CHAR);
      VAR k: INTEGER;
    BEGIN
      k := 0;
      WHILE (k < LEN(s)) & (s[k] # 0X) & (i < LEN(command) - 1) DO command[i] := s[k]; INC(i); INC(k) END
    END Add;

  BEGIN
    i := 0; Add("COPY "); Add(from); Add(" "); Add(to); command[i] := 0X;
    RETURN Platform.System(command) = 0
  END Copy;

  (* Whether the file called name is an object in the form Put writes:
     on VMS, any object, whose records VMS keeps (doc/developer/
     vax-macro32-backend.md, section 13.1); the Linker checks the rest *)
  PROCEDURE IsCounted*(name: ARRAY OF CHAR): BOOLEAN;
  BEGIN
    RETURN TRUE
  END IsCounted;

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
