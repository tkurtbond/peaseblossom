MODULE RecordsTest;

  (* vax-objconvert-counted (doc/developer/vax-macro32-backend.md, section
     13.2, proposals 1 and 2): RecordFiles' Open, Get and CreateFixed on
     VMS. Records of 0, 1 and 512 bytes written and read back; a Stream_LF
     file, a fixed-length one and a missing one not opened; then a
     600-byte record read into 100 bytes, which stops the program with a
     message and HALT(99). *)

  IMPORT Files, Out, RecordFiles;

  VAR
    f: RecordFiles.File; g: Files.File; r: Files.Rider;
    bytes: ARRAY 600 OF CHAR; small: ARRAY 100 OF CHAR;
    length: INTEGER; read: BOOLEAN;

  (* bytes, each its index MOD 256 *)
  PROCEDURE Fill;
    VAR i: INTEGER;
  BEGIN
    FOR i := 0 TO LEN(bytes) - 1 DO bytes[i] := CHR(i MOD 256) END
  END Fill;

  (* whether bytes' first n are as Fill makes them *)
  PROCEDURE AsWritten(n: INTEGER): BOOLEAN;
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE (i < n) & (bytes[i] = CHR(i MOD 256)) DO INC(i) END;
    RETURN i = n
  END AsWritten;

  PROCEDURE Refused(name, what: ARRAY OF CHAR);
  BEGIN
    Out.String(name);
    IF RecordFiles.Open(name) = NIL THEN Out.String(" not opened: ") ELSE Out.String(" opened: ") END;
    Out.String(what); Out.Ln
  END Refused;

BEGIN
  Fill;
  f := RecordFiles.Create("RECORDS.DAT", 600);
  RecordFiles.Put(f, bytes, 0); RecordFiles.Put(f, bytes, 1); RecordFiles.Put(f, bytes, 512);
  RecordFiles.Close(f);
  f := RecordFiles.Open("RECORDS.DAT");
  IF f = NIL THEN
    Out.String("RECORDS.DAT not opened"); Out.Ln
  ELSE
    LOOP
      bytes[0] := 0FFX;
      IF ~RecordFiles.Get(f, bytes, length) THEN EXIT END;
      Out.String("a record of "); Out.Int(length, 0); Out.String(" bytes");
      IF AsWritten(length) THEN Out.String(", as written") ELSE Out.String(", not as written") END;
      Out.Ln; Fill
    END;
    Out.String("the end of RECORDS.DAT"); Out.Ln;
    RecordFiles.Close(f)
  END;
  g := Files.New("STREAM.TXT"); Files.Set(r, g, 0); Files.Write(r, "x"); Files.Write(r, 0AX);
  Files.Register(g); Files.Close(g);
  Refused("STREAM.TXT", "Stream_LF");
  f := RecordFiles.CreateFixed("FIXED.DAT", 512);
  RecordFiles.Put(f, bytes, 512); RecordFiles.Close(f);
  Refused("FIXED.DAT", "fixed-length");
  Refused("MISSING.DAT", "not there");
  f := RecordFiles.Create("LONG.DAT", 600);
  RecordFiles.Put(f, bytes, 600); RecordFiles.Close(f);
  f := RecordFiles.Open("LONG.DAT");
  Out.String("reading a record of 600 bytes into 100"); Out.Ln;
  read := RecordFiles.Get(f, small, length);
  Out.String("not stopped"); Out.Ln
END RecordsTest.
