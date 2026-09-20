MODULE outtest;
  (* PLAN.md Phase 10 step 5: rtl/llvm/Out.Mod - characters, strings,
     integers in decimal and hexadecimal, REAL and LONGREAL in exponential
     form, through what poc's Out shares with voc's own (test.sh runs this
     same source under both and requires the same output - for the real
     numbers that means the algorithm was carried over exactly, right or
     wrong in the last digit). No real literal is large or integral, which
     voc's compiler rejects; the numbers are built by arithmetic. *)
  IMPORT Out;
  VAR
    k, n: INTEGER;
    x, y, one, two, three, ten: LONGREAL;
    r: REAL;

  PROCEDURE Show(x: LONGREAL);
  BEGIN
    Out.LongReal(x, 0); Out.Ln;
    Out.LongReal(x, 8); Out.Ln;
    Out.LongReal(x, 12); Out.Ln;
    Out.LongReal(x, 16); Out.Ln;
    Out.LongReal(x, 24); Out.Ln;
    Out.LongReal(x, 30); Out.Ln
  END Show;

  PROCEDURE ShowReal(x: REAL);
  BEGIN
    Out.Real(x, 0); Out.Ln;
    Out.Real(x, 7); Out.Ln;
    Out.Real(x, 10); Out.Ln;
    Out.Real(x, 14); Out.Ln;
    Out.Real(x, 20); Out.Ln
  END ShowReal;

BEGIN
  Out.Open;
  (* real constants voc's compiler folds are written to its C with 15
     digits and read back as a different number, so what is divided is
     only known at run time *)
  one := 1.0D0; two := 2.0D0; three := 3.0D0; ten := 10.0D0;
  (* strings and characters *)
  Out.String("Hello, Peaseblossom!"); Out.Ln;
  Out.String(""); Out.Ln;
  Out.Char("x"); Out.Char("y"); Out.Char(" "); Out.Char("z"); Out.Ln;
  Out.Flush;

  (* Int: sign, zero, field widths, the extremes *)
  Out.Int(0, 0); Out.Ln;
  Out.Int(7, 1); Out.Char("|"); Out.Ln;
  Out.Int(-7, 0); Out.Ln;
  Out.Int(-1234, 8); Out.Char("|"); Out.Ln;
  Out.Int(1234, 2); Out.Ln;
  Out.Int(5, 40); Out.Char("|"); Out.Ln;
  Out.Int(MAX(INTEGER), 0); Out.Ln;
  Out.Int(MIN(INTEGER), 0); Out.Ln;
  Out.Int(MAX(LONGINT), 0); Out.Ln;
  Out.Int(MIN(LONGINT), 0); Out.Ln;

  (* Hex: at least n digits, more if x needs them, all 16 if negative *)
  Out.Hex(0, 1); Out.Ln;
  Out.Hex(255, 1); Out.Ln;
  Out.Hex(255, 6); Out.Ln;
  Out.Hex(4095, 2); Out.Ln;
  Out.Hex(-1, 1); Out.Ln;
  Out.Hex(-256, 4); Out.Ln;
  Out.Hex(MAX(LONGINT), 0); Out.Ln;
  Out.Hex(1, 20); Out.Ln;

  (* LONGREAL: the powers of ten and their reciprocals, the third of a
     power, negatives, zero *)
  x := 0.0D0; Show(x);
  x := 1.0D0; Show(x);
  x := -1.0D0; Show(x);
  x := 0.5D0; Show(x);
  x := 3.14159265358979D0; Show(x);
  x := one / three; Show(x);
  x := -two / three; Show(x);
  x := 12345.6789D0; Show(x);
  x := one;
  FOR k := 1 TO 40 DO
    x := x * ten;
    IF (k = 1) OR (k = 9) OR (k = 15) OR (k = 22) OR (k = 23) OR (k = 30) OR (k = 40) THEN Show(x) END
  END;
  y := one;
  FOR k := 1 TO 40 DO
    y := y / ten;
    IF (k = 1) OR (k = 5) OR (k = 15) OR (k = 22) OR (k = 30) OR (k = 40) THEN Out.LongReal(y, 0); Out.Ln END
  END;
  x := one;
  FOR k := 1 TO 300 DO x := x * ten END;
  Out.LongReal(x, 0); Out.Ln;
  y := x / three; Out.LongReal(y, 0); Out.Ln;
  x := one;
  FOR k := 1 TO 300 DO x := x / ten END;
  Out.LongReal(x, 0); Out.Ln;

  (* REAL *)
  r := 0.0; ShowReal(r);
  r := 1.0; ShowReal(r);
  r := -1.5; ShowReal(r);
  r := 3.14159; ShowReal(r);
  r := SHORT(one / three); ShowReal(r);
  r := SHORT(123456.789D0); ShowReal(r);
  x := one;
  FOR k := 1 TO 30 DO
    x := x * ten;
    IF (k = 3) OR (k = 10) OR (k = 20) OR (k = 30) THEN r := SHORT(x); Out.Real(r, 0); Out.Ln END
  END;
  x := one;
  FOR k := 1 TO 30 DO
    x := x / ten;
    IF (k = 3) OR (k = 10) OR (k = 20) OR (k = 30) THEN r := SHORT(x); Out.Real(r, 0); Out.Ln END
  END;

  (* infinity and not a number, and their sign *)
  x := one;
  FOR k := 1 TO 400 DO x := x * ten END;
  Out.LongReal(x, 0); Out.Ln;
  Out.LongReal(-x, 12); Out.Ln;
  y := x - x;
  Out.LongReal(y, 0); Out.Ln;

  (* the table Ten prints from *)
  Out.LongReal(Out.Ten(0), 0); Out.Ln;
  Out.LongReal(Out.Ten(5), 0); Out.Ln;
  Out.LongReal(Out.Ten(22), 0); Out.Ln;

  (* not a terminal here *)
  IF Out.IsConsole THEN Out.String("terminal") ELSE Out.String("not a terminal") END;
  Out.Ln
END outtest.
