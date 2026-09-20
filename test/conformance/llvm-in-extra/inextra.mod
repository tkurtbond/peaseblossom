MODULE inextra;
  (* PLAN.md Phase 10 step 5, the parts of In specific to poc: HugeInt, hexadecimal
     and other numbers that are not, Name, real numbers read exactly (and
     refused when they are not numbers), a carriage return before the line
     feed. test.sh feeds it input.txt. What it prints goes through Out. *)
  IMPORT In, Out, SYSTEM;
  VAR
    h: HUGEINT;
    x: LONGREAL;
    r: REAL;
    name, line: ARRAY 16 OF CHAR;
    ch: CHAR;

  PROCEDURE Done;
  BEGIN
    IF In.Done THEN Out.String(" done") ELSE Out.String(" not done") END;
    Out.Ln
  END Done;

  PROCEDURE ShowLong(x: LONGREAL);
  BEGIN
    Out.Hex(SYSTEM.VAL(HUGEINT, x), 16)
  END ShowLong;

  PROCEDURE ShowShort(x: REAL);
  BEGIN
    Out.Hex(SYSTEM.VAL(LONGINT, x), 8)
  END ShowShort;

BEGIN
  (* integers beyond 32 bits, hexadecimal, not integers *)
  In.HugeInt(h); Out.String("HugeInt "); Out.Int(h, 0); Done;
  In.HugeInt(h); Out.String("HugeInt "); Out.Int(h, 0); Done;
  In.HugeInt(h); Out.String("HugeInt "); Out.Int(h, 0); Done;
  In.HugeInt(h); Out.String("HugeInt "); Out.Int(h, 0); Done;
  h := 5; In.HugeInt(h); Out.String("HugeInt "); Out.Int(h, 0); Done;
  h := 5; In.HugeInt(h); Out.String("HugeInt "); Out.Int(h, 0); Done;
  In.Line(line); Out.String("rest ["); Out.String(line); Out.Char("]"); Done;

  (* words *)
  In.Name(name); Out.String("Name ["); Out.String(name); Out.Char("]"); Done;
  In.Name(name); Out.String("Name ["); Out.String(name); Out.Char("]"); Done;
  In.Line(line);

  (* a carriage return before the line feed is not part of the line *)
  In.Line(line); Out.String("Line ["); Out.String(line); Out.Char("]"); Done;
  In.Line(line); Out.String("Line ["); Out.String(line); Out.Char("]"); Done;

  (* real numbers: read exactly, or refused and left as they were *)
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  x := 1.0D0;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.LongReal(x); Out.String("LongReal "); ShowLong(x); Done;
  In.Real(r); Out.String("Real "); ShowShort(r); Done;
  In.Real(r); Out.String("Real "); ShowShort(r); Done;
  r := 1.0;
  In.Real(r); Out.String("Real "); ShowShort(r); Done;

  (* the end of the input *)
  In.LongReal(x); Out.String("LongReal at the end"); Done;
  In.Name(name); Out.String("Name at the end"); Done;
  In.Char(ch); Out.String("Char at the end"); Done
END inextra.
