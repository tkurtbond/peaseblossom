MODULE instr;
  (* InStr (Phase 15's "Ongoing library enhancements" 2). With the argument
     "in", reads standard input with In; with "instr", reads all of it into
     a string with In.Char, then the same tokens from the string with
     InStr, also writing pos after each ("pos" lines). test.sh checks that
     the two agree, apart from those. Then, with "instr", what only InStr
     has: a position that moves only on success, and strings and positions
     at their edges. *)
  IMPORT In, InStr, Out, Modules;
  VAR
    mode: ARRAY 8 OF CHAR; useIn: BOOLEAN;
    text: ARRAY 4096 OF CHAR; pos: LONGINT; n: LONGINT; ch: CHAR;
    i: INTEGER; l: LONGINT; h: HUGEINT; x: REAL; y: LONGREAL; word: ARRAY 64 OF CHAR;
    short: ARRAY 4 OF CHAR; full: ARRAY 5 OF CHAR;

  PROCEDURE Done(done: BOOLEAN);
  BEGIN
    IF done THEN Out.String(" Done") ELSE Out.String(" not Done") END; Out.Ln;
    IF ~useIn THEN Out.String("pos "); Out.Int(pos, 0); Out.Ln END
  END Done;

  PROCEDURE Status(label: ARRAY OF CHAR);
  BEGIN
    Out.String(label); Out.String(": pos "); Out.Int(pos, 0);
    IF InStr.Done THEN Out.String(" Done") ELSE Out.String(" not Done") END
  END Status;

BEGIN
  Modules.GetArg(1, mode); useIn := mode = "in";
  IF ~useIn THEN
    n := 0; In.Open; In.Char(ch);
    WHILE In.Done DO text[n] := ch; INC(n); In.Char(ch) END;
    text[n] := 0X; pos := 0
  END;
  (* the same calls either way *)
  IF useIn THEN In.Int(i) ELSE InStr.Int(i, text, pos) END;
  Out.String("Int "); Out.Int(i, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Int(i) ELSE InStr.Int(i, text, pos) END;
  Out.String("Int "); Out.Int(i, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.LongInt(l) ELSE InStr.LongInt(l, text, pos) END;
  Out.String("LongInt "); Out.Int(l, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.HugeInt(h) ELSE InStr.HugeInt(h, text, pos) END;
  Out.String("HugeInt "); Out.Int(h, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Name(word) ELSE InStr.Name(word, text, pos) END;
  Out.String("Name "); Out.String(word); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.String(word) ELSE InStr.String(word, text, pos) END;
  Out.String("String "); Out.String(word); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Char(ch) ELSE InStr.Char(ch, text, pos) END;
  Out.String("Char "); Out.Int(ORD(ch), 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Real(x) ELSE InStr.Real(x, text, pos) END;
  Out.String("Real "); Out.Real(x, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.LongReal(y) ELSE InStr.LongReal(y, text, pos) END;
  Out.String("LongReal "); Out.LongReal(y, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Name(word) ELSE InStr.Name(word, text, pos) END;
  Out.String("Name "); Out.String(word); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Line(word) ELSE InStr.Line(word, text, pos) END;
  Out.String("Line "); Out.String(word); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Int(i) ELSE InStr.Int(i, text, pos) END;
  Out.String("Int "); Out.Int(i, 0); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Name(word) ELSE InStr.Name(word, text, pos) END;
  Out.String("Name "); Out.String(word); Done(useIn & In.Done OR ~useIn & InStr.Done);
  IF useIn THEN In.Char(ch) ELSE InStr.Char(ch, text, pos) END;
  Out.String("Char "); Out.Int(ORD(ch), 0); Done(useIn & In.Done OR ~useIn & InStr.Done);

  IF ~useIn THEN
    Out.String("-- InStr only"); Out.Ln;
    (* a failure leaves pos where it was, the next call reads from there *)
    pos := 0; InStr.Int(i, "  12ab 7", pos); Status("12ab"); Out.Int(i, 3); Out.Ln;
    InStr.Name(word, "  12ab 7", pos); Status("then Name"); Out.Char(" "); Out.String(word); Out.Ln;
    InStr.Int(i, "  12ab 7", pos); Status("then Int"); Out.Int(i, 3); Out.Ln;
    pos := 0; InStr.Real(x, "1.5e", pos); Status("1.5e"); Out.Ln;
    pos := 0; InStr.String(word, '"unended', pos); Status("unended string"); Out.Ln;
    (* several numbers on one line, and on several *)
    pos := 0; InStr.Real(x, "0.5 -2.5E1 3", pos); Out.Real(x, 0);
    InStr.Real(x, "0.5 -2.5E1 3", pos); Out.Real(x, 0);
    InStr.Real(x, "0.5 -2.5E1 3", pos); Out.Real(x, 0); Status(" three reals"); Out.Ln;
    (* a string with no 0X ends at its length *)
    full[0] := "1"; full[1] := "2"; full[2] := "3"; full[3] := "4"; full[4] := "5";
    pos := 0; InStr.Int(i, full, pos); Status("no 0X"); Out.Int(i, 6); Out.Ln;
    InStr.Char(ch, full, pos); Status("then Char"); Out.Ln;
    (* positions at the edges *)
    pos := -1; InStr.Char(ch, "abc", pos); Status("pos -1"); Out.Ln;
    pos := 3; InStr.Char(ch, "abc", pos); Status("pos 3, the end"); Out.Ln;
    pos := 3; InStr.Line(word, "abc", pos); Status("Line at the end"); Out.Ln;
    pos := 4; InStr.Name(word, "abc", pos); Status("pos 4, past the end"); Out.Ln;
    pos := 2; InStr.Char(ch, "abc", pos); Status("pos 2"); Out.Char(" "); Out.Char(ch); Out.Ln;
    (* what does not fit is left for the next call, as In does *)
    pos := 0; InStr.Line(short, "abcdef", pos); Status("Line in 4"); Out.Char(" "); Out.String(short); Out.Ln;
    InStr.Line(short, "abcdef", pos); Status("the rest"); Out.Char(" "); Out.String(short); Out.Ln
  END
END instr.
