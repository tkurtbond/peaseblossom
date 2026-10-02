MODULE oberon;

  (* Oberon under poc and voc: the parameters (the program's arguments,
     read with a scanner as a command reads them), the log echoed to
     standard output, the clocks (only their ranges: they change), the
     empty selection, OptionChar. *)

  IMPORT Oberon, Texts, Out;

  VAR
    S: Texts.Scanner; W: Texts.Writer; T: Texts.Text;
    beg, end, time, t, d, t0: LONGINT;

BEGIN
  Out.String("par "); Out.Int(Oberon.Par.text.len, 0); Out.Int(Oberon.Par.pos, 2); Out.Ln;
  Texts.OpenScanner(S, Oberon.Par.text, Oberon.Par.pos); Texts.Scan(S);
  WHILE ~S.eot DO
    Out.Int(S.class, 0);
    CASE S.class OF
      Texts.Name, Texts.String: Out.String(" "); Out.String(S.s)
    | Texts.Int: Out.Int(S.i, 2)
    | Texts.Char: Out.String(" "); Out.Char(S.c)
    ELSE
    END;
    Out.Ln; Texts.Scan(S)
  END;

  Texts.OpenWriter(W);
  Texts.WriteString(W, "to the log "); Texts.WriteInt(W, 42, 0); Texts.WriteLn(W);
  Texts.WriteString(W, "second line"); Texts.WriteLn(W);
  Texts.Append(Oberon.Log, W.buf);
  Out.String("log "); Out.Int(Oberon.Log.len, 0); Out.Ln;
  Texts.WriteString(W, "inserted"); Texts.WriteLn(W); Texts.Insert(Oberon.Log, 0, W.buf);

  Oberon.GetSelection(T, beg, end, time);
  IF (T = NIL) & (beg = 0) & (end = 0) & (time = 0) THEN Out.String("no selection") END; Out.Ln;
  Out.Char(Oberon.OptionChar); Out.Ln;

  t0 := Oberon.Time(); IF t0 >= 0 THEN Out.String("time ok") END; Out.Ln;
  Oberon.GetClock(t, d);
  IF (t DIV 4096 < 24) & (t DIV 64 MOD 64 < 60) & (t MOD 64 < 61)
   & (d DIV 32 MOD 16 >= 1) & (d DIV 32 MOD 16 <= 12) & (d MOD 32 >= 1) THEN
    Out.String("clock ok")
  END;
  Out.Ln
END oberon.
