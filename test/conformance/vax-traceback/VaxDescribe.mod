MODULE VaxDescribe;
  (* PLAN.md Phase 18 step 5b: RecordFiles.Describe, which gives poc -g
     on VMS its source file's resultant name and RMS attributes for the
     debugger (doc/developer/vax-object-language.md, section 16.6): of
     VaxTrace.mod, sent here, its name after the directory, which differs
     between the guest's accounts, whether its creation time is set, and
     its end-of-file block, first free byte and record format (2,
     variable); then of a file that does not exist *)
  IMPORT RecordFiles, Out;

  PROCEDURE Show(file: ARRAY OF CHAR);
    VAR name: ARRAY 256 OF CHAR; created: ARRAY 8 OF CHAR; endBlock, firstFree, format: LONGINT;
        i, after: INTEGER; set: BOOLEAN;
  BEGIN
    IF RecordFiles.Describe(file, name, created, endBlock, firstFree, format) THEN
      i := 0; after := 0;
      WHILE name[i] # 0X DO
        IF name[i] = "]" THEN after := i + 1 END;
        INC(i)
      END;
      i := after;
      WHILE name[i] # 0X DO Out.Char(name[i]); INC(i) END;
      set := FALSE;
      FOR i := 0 TO 7 DO IF created[i] # 0X THEN set := TRUE END END;
      IF set THEN Out.String(" created") ELSE Out.String(" not created") END;
      Out.Char(" "); Out.Int(endBlock, 0); Out.Char(" "); Out.Int(firstFree, 0);
      Out.Char(" "); Out.Int(format, 0); Out.Ln
    ELSE
      Out.String("cannot describe "); Out.String(file); Out.Ln
    END
  END Show;

BEGIN
  Show("VaxTrace.mod");
  Show("NOSUCH.FILE")
END VaxDescribe.
