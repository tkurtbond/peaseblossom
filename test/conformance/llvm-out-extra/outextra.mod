MODULE outextra;
  (* PLAN.md Phase 10 step 5, the parts of Out specific to poc: the
     smallest HUGEINT, a negative field width, output written before the
     program ends without a line end, and Out and Console interleaving in
     the order of the calls; and real numbers voc prints with a wrong last
     digit or exponent (llvm-out has the ones both agree on, and
     llvm-real-digits checks many more against an oracle). *)
  IMPORT Out, Console;
  VAR k: INTEGER; x, y, one, two, three, ten: LONGREAL; r: REAL;
BEGIN
  Out.Int(MIN(HUGEINT), 0); Out.Ln;
  Out.Int(MIN(HUGEINT), 25); Out.Char("|"); Out.Ln;
  Out.Int(MAX(HUGEINT), 0); Out.Ln;
  Out.Int(12, -5); Out.Char("|"); Out.Ln;
  Out.String("one "); Console.String("two "); Out.String("three "); Console.String("four"); Out.Ln;
  Out.Char("a"); Console.Char("b"); Out.Char("c"); Console.Ln;
  one := 1.0D0; two := 2.0D0; three := 3.0D0; ten := 10.0D0;
  (* the doubles nearest a third, minus two thirds and 12345.6789 are
     0.33333333333333331483, 0.66666666666666662966 and 12345.678900000000795 *)
  x := one / three; Out.LongReal(x, 0); Out.Ln; Out.LongReal(x, 24); Out.Ln;
  x := -two / three; Out.LongReal(x, 24); Out.Ln;
  x := 12345.6789D0; Out.LongReal(x, 24); Out.Ln;
  (* 10^23 is not a double: the product of 23 tens is the one below it,
     9.9999999999999991611...D+22 *)
  x := one;
  FOR k := 1 TO 40 DO
    x := x * ten;
    IF (k = 23) OR (k = 30) OR (k = 40) THEN Out.LongReal(x, 0); Out.Ln; Out.LongReal(x, 24); Out.Ln END
  END;
  x := one;
  FOR k := 1 TO 300 DO x := x * ten END;
  Out.LongReal(x, 0); Out.Ln;
  y := one;
  FOR k := 1 TO 20 DO y := y / ten END;
  r := SHORT(y); Out.Real(r, 0); Out.Ln; Out.Real(r, 12); Out.Ln;
  Out.String("no line end at the end")
END outextra.
