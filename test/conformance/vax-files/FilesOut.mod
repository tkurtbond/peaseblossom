MODULE FilesOut;
  (* PLAN.md Phase 16 step 4 (doc/developer/vax-macro32-backend.md, section
     15, proposal 2): Files, writing and reading back a text file, every
     byte value (1300 bytes: two block ends and an odd length) before and
     after Register, strings, an empty file, a file registered twice, and
     reading two files made elsewhere, FILESVAR.TXT and FILESVFC.TXT - on
     VMS a variable-length and a VFC one, on Unix plain text *)
  IMPORT Files, Out;
  VAR f, g: Files.File; r, w: Files.Rider; s: ARRAY 8 OF CHAR; ch: CHAR; i, bad: LONGINT; res: INTEGER;

  PROCEDURE Bool(text: ARRAY OF CHAR; b: BOOLEAN);
  BEGIN
    Out.String(text); IF b THEN Out.String(" TRUE") ELSE Out.String(" FALSE") END; Out.Ln
  END Bool;

  PROCEDURE WriteLine(VAR w: Files.Rider; text: ARRAY OF CHAR);
    VAR i: INTEGER;
  BEGIN
    i := 0;
    WHILE text[i] # 0X DO Files.Write(w, text[i]); INC(i) END;
    Files.Write(w, 0AX)
  END WriteLine;

  (* the file's length and its lines *)
  PROCEDURE ShowLines(name: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; line: ARRAY 80 OF CHAR;
  BEGIN
    Out.String(name);
    f := Files.Old(name);
    IF f = NIL THEN Out.String(": none"); Out.Ln
    ELSE
      Out.String(": "); Out.Int(Files.Length(f), 0); Out.String(" bytes"); Out.Ln;
      Files.Set(r, f, 0);
      LOOP
        Files.ReadLine(r, line);
        IF r.eof & (line[0] = 0X) THEN EXIT END;
        Out.String("  ["); Out.String(line); Out.String("]"); Out.Ln;
        IF r.eof THEN EXIT END
      END;
      Files.Close(f)
    END
  END ShowLines;

BEGIN
  f := Files.New("FILESOUT.TXT");
  Files.Set(w, f, 0);
  WriteLine(w, "first line"); WriteLine(w, ""); WriteLine(w, "the third, ended by spaces  ");
  Files.Register(f); Files.Close(f);
  ShowLines("FILESOUT.TXT");

  f := Files.New("FILESOUT.BIN");
  Files.Set(w, f, 0);
  FOR i := 0 TO 1299 DO Files.Write(w, CHR(i MOD 256)) END;
  Files.Set(r, f, 700); Files.Read(r, ch);
  Out.String("before Register, byte 700: "); Out.Int(ORD(ch), 0); Out.Ln;
  Files.Register(f); Files.Close(f);
  g := Files.Old("FILESOUT.BIN");
  Out.String("FILESOUT.BIN: "); Out.Int(Files.Length(g), 0); Out.String(" bytes"); Out.Ln;
  Files.Set(r, g, 0); bad := 0;
  FOR i := 0 TO 1299 DO Files.Read(r, ch); IF ORD(ch) # i MOD 256 THEN INC(bad) END END;
  Out.String("bytes that differ: "); Out.Int(bad, 0); Out.Ln;
  Bool("eof before the end:", r.eof);
  Files.Read(r, ch);
  Bool("eof at the end:", r.eof);
  Bool("Base:", Files.Base(r) = g);
  Files.Close(g);

  f := Files.New("FILESOUT.STR");
  Files.Set(w, f, 0); Files.WriteString(w, "abc"); Files.WriteString(w, "de");
  Files.Register(f); Files.Close(f);
  g := Files.Old("FILESOUT.STR");
  Out.String("FILESOUT.STR: "); Out.Int(Files.Length(g), 0); Out.String(" bytes"); Out.Ln;
  Files.Set(r, g, 0);
  Files.ReadString(r, s); Out.String("  ["); Out.String(s); Out.String("]"); Out.Ln;
  Files.ReadString(r, s); Out.String("  ["); Out.String(s); Out.String("]"); Out.Ln;
  Files.Close(g);

  f := Files.New("FILESOUT.EMP"); Files.Register(f); Files.Close(f);
  ShowLines("FILESOUT.EMP");

  f := Files.New("FILESOUT.TXT");
  Files.Set(w, f, 0); WriteLine(w, "the second version");
  Files.Register(f); Files.Close(f);
  ShowLines("FILESOUT.TXT");

  ShowLines("FILESVAR.TXT"); ShowLines("FILESVFC.TXT"); ShowLines("NO-SUCH-FILE.TXT");

  Files.Delete("FILESOUT.BIN", res); Bool("deleted:", res = 0);
  Bool("gone:", Files.Old("FILESOUT.BIN") = NIL);
  Files.Delete("FILESOUT.BIN", res); Bool("deleted a missing file:", res = 0)
END FilesOut.
