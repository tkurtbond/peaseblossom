MODULE FileBytes;

  (* vax-texts' dump of the files TextsUse writes, which tools/vax-do cannot
     bring back whole, since it copies text only: for each file named on
     the command line, "== <name> <length>", then its bytes in hexadecimal,
     upper case, 16 to a line; "== <name> missing" if there is no such file.
     test.sh makes the same with od from the files the LLVM build writes. *)

  IMPORT Args, Files, Out;

  VAR
    i, column: INTEGER;
    name: ARRAY 64 OF CHAR;
    f: Files.File; r: Files.Rider;
    byte: CHAR;

  PROCEDURE HexDigit(n: INTEGER);
  BEGIN
    IF n < 10 THEN Out.Char(CHR(n + ORD("0"))) ELSE Out.Char(CHR(n - 10 + ORD("A"))) END
  END HexDigit;

BEGIN
  i := 1;
  WHILE i < Args.argc DO
    Args.Get(i, name);
    Out.String("== "); Out.String(name);
    f := Files.Old(name);
    IF f = NIL THEN
      Out.String(" missing"); Out.Ln
    ELSE
      Out.Char(" "); Out.Int(Files.Length(f), 0); Out.Ln;
      Files.Set(r, f, 0); Files.Read(r, byte); column := 0;
      WHILE ~r.eof DO
        HexDigit(ORD(byte) DIV 16); HexDigit(ORD(byte) MOD 16); INC(column);
        IF column = 16 THEN Out.Ln; column := 0 END;
        Files.Read(r, byte)
      END;
      IF column > 0 THEN Out.Ln END;
      Files.Close(f)
    END;
    INC(i)
  END
END FileBytes.
