MODULE intest;
  (* PLAN.md Phase 10 step 5: rtl/llvm/In.Mod - integers, lines, quoted
     strings, real numbers and single characters read from standard input,
     through what poc's In shares with voc's own (test.sh runs this same
     source, fed the same input, under both and requires the same output).
     What it prints goes through Out. *)
  IMPORT In, Out;
  VAR
    i: INTEGER;
    l: LONGINT;
    r: REAL;
    x: LONGREAL;
    ch: CHAR;
    line: ARRAY 40 OF CHAR;
    small: ARRAY 6 OF CHAR;

  PROCEDURE Done;
  BEGIN
    IF In.Done THEN Out.String(" done") ELSE Out.String(" not done") END;
    Out.Ln
  END Done;

BEGIN
  In.Open;
  (* numbers on one line: decimal, negative, hexadecimal, the largest LONGINT (HugeInt is only in llvm-in-extra: voc's takes a
     SYSTEM.INT64, a type of its own) *)
  In.Int(i); Out.String("Int "); Out.Int(i, 0); Done;
  In.Int(i); Out.String("Int "); Out.Int(i, 0); Done;
  In.LongInt(l); Out.String("LongInt "); Out.Int(l, 0); Done;
  In.LongInt(l); Out.String("LongInt "); Out.Int(l, 0); Done;
  In.LongInt(l); Out.String("LongInt "); Out.Int(l, 0); Done;
  In.LongInt(l); Out.String("LongInt "); Out.Int(l, 0); Done;
  In.Line(line); Out.String("rest ["); Out.String(line); Out.Char("]"); Done;

  (* lines, a line too long for the array *)
  In.Line(line); Out.String("Line ["); Out.String(line); Out.Char("]"); Done;
  In.Line(small); Out.String("Line ["); Out.String(small); Out.Char("]"); Done;
  In.Line(line); Out.String("rest ["); Out.String(line); Out.Char("]"); Done;

  (* a quoted string, and what follows it *)
  In.String(line); Out.String("String ["); Out.String(line); Out.Char("]"); Done;
  In.Line(line); Out.String("rest ["); Out.String(line); Out.Char("]"); Done;

  (* real numbers, a line each *)
  In.Real(r); Out.String("Real "); Out.Real(r, 0); Done;
  In.LongReal(x); Out.String("LongReal "); Out.LongReal(x, 0); Done;
  In.LongReal(x); Out.String("LongReal "); Out.LongReal(x, 0); Done;
  In.LongReal(x); Out.String("LongReal "); Out.LongReal(x, 0); Done;

  (* single characters, line ends included, then the end of the input *)
  In.Char(ch); Out.String("Char "); Out.Int(ORD(ch), 0); Done;
  In.Char(ch); Out.String("Char "); Out.Int(ORD(ch), 0); Done;
  In.Char(ch); Out.String("Char "); Out.Int(ORD(ch), 0); Done;
  In.Char(ch); Out.String("Char "); Out.Int(ORD(ch), 0); Done;
  In.Char(ch); Out.String("Char "); Out.Int(ORD(ch), 0); Done;
  In.Int(i); Out.String("Int after the end"); Done;
  In.Line(line); Out.String("Line after the end"); Done
END intest.
