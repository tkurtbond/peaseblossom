MODULE riders;
  (* PLAN.md Phase 12 step 5d: Files' typed riders and the rest of voc's
     interface, under poc and voc, both size models (test.sh compares).
     The file's bytes are dumped in hex, so the format (Oakwood 1.2.5.4)
     is compared too; the values read back are the ones voc reads right
     under both models (no negative INTEGER or LONGINT: signed.mod). *)
  IMPORT SYSTEM, Files, Out;
  VAR
    f, g: Files.File; r: Files.Rider;
    b: BOOLEAN; c: CHAR; s: SHORTINT; y: SYSTEM.BYTE; i: INTEGER; l: LONGINT; h: HUGEINT;
    set: SET; x: REAL; lx: LONGREAL; str: ARRAY 16 OF CHAR; buf: ARRAY 8 OF CHAR;
    k, t, d: LONGINT; res: INTEGER;

  PROCEDURE Dump(f: Files.File);
    VAR r: Files.Rider; ch: CHAR; n: LONGINT; hex: ARRAY 17 OF CHAR;
  BEGIN
    hex := "0123456789ABCDEF";
    Files.Set(r, f, 0); n := 0;
    Files.Read(r, ch);
    WHILE ~r.eof DO
      Out.Char(hex[ORD(ch) DIV 16]); Out.Char(hex[ORD(ch) MOD 16]);
      INC(n); IF n MOD 16 = 0 THEN Out.Ln ELSE Out.Char(" ") END;
      Files.Read(r, ch)
    END;
    Out.Ln
  END Dump;

BEGIN
  Out.String("max lengths positive: ");
  IF (Files.MaxPathLength > 0) & (Files.MaxNameLength > 0) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  f := Files.New("riders.bin"); Files.Set(r, f, 0);
  Files.WriteBool(r, TRUE); Files.WriteBool(r, FALSE);
  Files.WriteInt(r, 1234); Files.WriteInt(r, 32767);
  Files.WriteLInt(r, 123456789); Files.WriteLInt(r, 7FFFFFFFH);
  Files.WriteSet(r, {0, 5, 9, 31});
  Files.WriteReal(r, 1.5); Files.WriteLReal(r, -2.25D0);
  Files.WriteString(r, "abc");
  Files.WriteNum(r, 0); Files.WriteNum(r, 63); Files.WriteNum(r, 64); Files.WriteNum(r, -64);
  Files.WriteNum(r, -65); Files.WriteNum(r, 300); Files.WriteNum(r, -300); Files.WriteNum(r, 123456789);
  buf := "xyzw"; Files.WriteBytes(r, buf, 3);
  Files.Write(r, "Q"); Files.Write(r, 7);
  Files.Register(f);
  f := Files.Old("riders.bin");
  Out.String("length "); Out.Int(Files.Length(f), 0); Out.Ln;
  Dump(f);

  Files.Set(r, f, 0);
  Files.ReadBool(r, b); Out.String("bool "); IF b THEN Out.String("TRUE") ELSE Out.String("FALSE") END;
  Files.ReadBool(r, b); IF b THEN Out.String(" TRUE") ELSE Out.String(" FALSE") END; Out.Ln;
  Files.ReadInt(r, i); Out.String("int "); Out.Int(i, 0);
  Files.ReadInt(r, i); Out.Int(i, 6); Out.Ln;
  Files.ReadLInt(r, l); Out.String("lint "); Out.Int(l, 0);
  Files.ReadLInt(r, l); Out.Int(l, 11); Out.Ln;
  Files.ReadSet(r, set); Out.String("set");
  FOR k := 0 TO 31 DO IF k IN set THEN Out.Int(k, 3) END END; Out.Ln;
  Files.ReadReal(r, x); Files.ReadLReal(r, lx); Out.String("reals ");
  Out.Int(ENTIER(x * 10), 0); Out.Int(ENTIER(lx * 100), 5); Out.Ln;
  Files.ReadString(r, str); Out.String("string "); Out.String(str); Out.Ln;
  Out.String("nums");
  FOR k := 1 TO 7 DO Files.ReadNum(r, l); Out.Int(l, 5) END;
  Files.ReadNum(r, l); Out.Int(l, 10); Out.Ln;
  Files.ReadBytes(r, buf, 3); buf[3] := 0X; Out.String("bytes "); Out.String(buf);
  Out.Int(r.res, 2); Out.Ln;
  Files.Read(r, c); Out.String("read into CHAR "); Out.Char(c); Out.Ln;
  Files.Set(r, f, 0); Files.Read(r, b); Out.String("read into BOOLEAN ");
  IF b THEN Out.String("TRUE") ELSE Out.String("FALSE") END; Out.Ln;
  Files.Set(r, f, Files.Length(f) - 1); Files.ReadByte(r, y);
  Out.String("read into BYTE "); Out.Int(SYSTEM.VAL(SYSTEM.INT8, y), 0); Out.Ln;
  Files.Set(r, f, Files.Length(f) - 2);
  buf := "......."; Files.ReadBytes(r, buf, 5);
  Out.String("short read res "); Out.Int(r.res, 0); Out.String(" eof ");
  IF r.eof THEN Out.String("TRUE") ELSE Out.String("FALSE") END; Out.Ln;

  Files.GetName(f, str); Out.String("name "); Out.String(str); Out.Ln;
  Files.GetDate(f, t, d);
  Out.String("date plausible ");
  IF (d DIV 32 MOD 16 IN {1..12}) & (d MOD 32 IN {1..31}) & (t DIV 4096 < 24) THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln;
  Files.Purge(f); Out.String("purged length "); Out.Int(Files.Length(f), 0); Out.Ln;
  Files.Close(f);

  (* the search path: riders.sub/inner.txt is found as inner.txt *)
  g := Files.Old("inner.txt");
  Out.String("without the path "); IF g = NIL THEN Out.String("NIL") ELSE Out.String("found") END; Out.Ln;
  Files.SetSearchPath("nowhere; riders.sub ;.");
  g := Files.Old("inner.txt");
  Out.String("with the path "); IF g = NIL THEN Out.String("NIL") ELSE Out.String("found") END;
  IF g # NIL THEN Files.Set(r, g, 0); Files.ReadLine(r, str); Out.Char(" "); Out.String(str); Files.GetName(g, str); Out.Char(" "); Out.String(str) END;
  Out.Ln;
  Files.SetSearchPath("");
  Files.ChangeDirectory("riders.sub", res); Out.String("chdir "); Out.Int(res, 0);
  g := Files.Old("inner.txt");
  IF g = NIL THEN Out.String(" NIL") ELSE Out.String(" found") END;
  Files.ChangeDirectory("..", res); Out.Int(res, 2); Out.Ln;
  (* voc's res is 2 here: its Delete first renames a file it has open
     out of the way, then cannot unlink the name *)
  Files.Delete("riders.bin", res);
  Out.String("deleted "); IF Files.Old("riders.bin") = NIL THEN Out.String("yes") ELSE Out.String("no") END; Out.Ln
END riders.
