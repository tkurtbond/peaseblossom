MODULE Versions;
  IMPORT Files, Out;

  VAR res: INTEGER;

  PROCEDURE Write(text: ARRAY OF CHAR);
    VAR f: Files.File; r: Files.Rider; i: INTEGER;
  BEGIN
    f := Files.New("NOTES.TXT"); Files.Set(r, f, 0);
    i := 0;
    WHILE text[i] # 0X DO Files.Write(r, text[i]); INC(i) END;
    Files.Write(r, 0AX);
    Files.Register(f); Files.Close(f)
  END Write;

  PROCEDURE Show;
    VAR f: Files.File; r: Files.Rider; ch: CHAR;
  BEGIN
    f := Files.Old("NOTES.TXT");
    IF f = NIL THEN
      Out.String("no NOTES.TXT"); Out.Ln
    ELSE
      Files.Set(r, f, 0); Files.Read(r, ch);
      WHILE ~r.eof DO
        IF ch = 0AX THEN Out.Ln ELSE Out.Char(ch) END;
        Files.Read(r, ch)
      END;
      Files.Close(f)
    END
  END Show;

BEGIN
  Write("the first version");
  Write("the second version");
  Show;
  Files.Delete("NOTES.TXT", res); Show;
  Files.Delete("NOTES.TXT", res); Show
END Versions.
