MODULE errtest;
  (* Phase 11 A26: rtl/llvm/Err.Mod, Out's interface on standard error.
     Every item is written to Out and then the same to Err, so standard
     output and standard error must carry the same text (test.sh compares
     them), and with both on one file the lines come in pairs, in the order
     of the calls: nothing is buffered. The last line is left without a Ln
     on both, and must still come out. *)
  IMPORT Out, Err;
  VAR
    one, three: LONGREAL;
    big: HUGEINT;

  PROCEDURE Text(s: ARRAY OF CHAR);
  BEGIN
    Out.String(s); Out.Ln;
    Err.String(s); Err.Ln
  END Text;

  PROCEDURE Int(x, n: HUGEINT);
  BEGIN
    Out.Char("["); Out.Int(x, n); Out.Char("]"); Out.Ln;
    Err.Char("["); Err.Int(x, n); Err.Char("]"); Err.Ln
  END Int;

  PROCEDURE Hex(x, n: HUGEINT);
  BEGIN
    Out.Hex(x, n); Out.Ln;
    Err.Hex(x, n); Err.Ln
  END Hex;

  PROCEDURE Reals(x: LONGREAL; n: INTEGER);
  BEGIN
    Out.Real(SHORT(x), n); Out.Char(" "); Out.LongReal(x, n); Out.Ln;
    Err.Real(SHORT(x), n); Err.Char(" "); Err.LongReal(x, n); Err.Ln
  END Reals;

BEGIN
  Out.Open; Err.Open;
  Text("text");
  Text("");
  Int(0, 0);
  Int(-42, 6);
  Int(123456789, 3);
  big := MIN(HUGEINT);
  Int(big, 22);
  Int(MAX(HUGEINT), 0);
  Hex(255, 1);
  Hex(-1, 4);
  one := 1; three := 3;
  Reals(one / three, 0);
  Reals(-one / three, 16);
  Reals(Out.Ten(5), 12);
  Reals(Err.Ten(5), 12);
  IF Out.IsConsole THEN Text("stdout is a terminal") ELSE Text("stdout is not a terminal") END;
  IF Err.IsConsole THEN Text("stderr is a terminal") ELSE Text("stderr is not a terminal") END;
  Out.String("no newline"); Out.Flush;
  Err.String(" at the end"); Err.Flush
END errtest.
