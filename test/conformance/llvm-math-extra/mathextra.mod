MODULE mathextra;
  (* PLAN.md Phase 10 step 6: rtl/llvm/Math.Mod and MathL.Mod where they
     differ from voc's or where voc is wrong - the properties of denormals,
     succ and pred either side of zero and at powers of two, the true
     cosine from sincos, results checked by their bits (poc's sqrt is
     correctly rounded, its constants are the right numbers), the errors of
     every kind at the edges of the range, the clamps of round. Poc only. *)
  IMPORT Math, MathL, Out, SYSTEM;

  VAR
    failures: INTEGER;
    x: LONGREAL;
    r: REAL;
    s, c: LONGREAL;
    rs, rc: REAL;

  PROCEDURE Fail(name: ARRAY OF CHAR);
  BEGIN INC(failures); Out.String("FAIL "); Out.String(name); Out.Ln END Fail;

  PROCEDURE Bits(name: ARRAY OF CHAR; x: LONGREAL; want: HUGEINT);
  BEGIN IF SYSTEM.VAL(HUGEINT, x) # want THEN Fail(name) END END Bits;

  PROCEDURE RBits(name: ARRAY OF CHAR; x: REAL; want: LONGINT);
  BEGIN IF SYSTEM.VAL(LONGINT, x) # want THEN Fail(name) END END RBits;

  PROCEDURE Same(name: ARRAY OF CHAR; got, want: LONGINT);
  BEGIN IF got # want THEN Fail(name); Out.Int(got, 0); Out.Ln END END Same;

  PROCEDURE Code(name: ARRAY OF CHAR; want: INTEGER);
  BEGIN
    IF Math.err # want THEN Fail(name); Out.Int(Math.err, 0); Out.Ln END;
    Math.ClearError
  END Code;

  PROCEDURE Constants;
  BEGIN
    Bits("MathL.pi", MathL.pi, 4614256656552045848);
    Bits("MathL.e", MathL.e, 4613303445314885481);
    Bits("MathL.large", MathL.large, 9218868437227405311);
    Bits("MathL.small", MathL.small, 4503599627370496);
    RBits("Math.pi", Math.pi, 1078530011);
    RBits("Math.e", Math.e, 1076754516);
    RBits("Math.large", Math.large, 2139095039);
    RBits("Math.small", Math.small, 8388608)
  END Constants;

  PROCEDURE Exact;
  BEGIN
    Bits("MathL.sqrt(2)", MathL.sqrt(2.0D0), 4609047870845172685);
    RBits("Math.sqrt(2)", Math.sqrt(2.0), 1068827891);
    (* sin and friends do not lose accuracy for large arguments *)
    x := MathL.scale(1.0D0, 60);
    IF ABS(MathL.sin(x) + 0.8306492176372546D0) > 1.0D-15 THEN Fail("MathL.sin(2^60)") END;
    r := Math.scale(1.0, 40);
    IF ABS(Math.sin(r) + 0.40570501153282873) > 1.0E-6 THEN Fail("Math.sin(2^40)") END
  END Exact;

  PROCEDURE Denormals;
  BEGIN
    x := MathL.scale(1.0D0, -1074); (* the smallest number: 2^-1074 *)
    Bits("smallest LONGREAL", x, 1);
    Same("MathL.exponent(denormal)", MathL.exponent(x), -1074);
    Bits("MathL.fraction(denormal)", MathL.fraction(x), 4607182418800017408);
    Bits("MathL.ulp(denormal)", MathL.ulp(x), 1);
    Bits("MathL.ulp(0)", MathL.ulp(0.0D0), 1);
    Bits("MathL.ulp(1)", MathL.ulp(1.0D0), 4372995238176751616); (* 2^-52 *)
    r := Math.scale(1.0, -149);
    RBits("smallest REAL", r, 1);
    Same("Math.exponent(denormal)", Math.exponent(r), -149);
    RBits("Math.fraction(denormal)", Math.fraction(r), 1065353216);
    RBits("Math.ulp(denormal)", Math.ulp(r), 1);
    RBits("Math.ulp(0)", Math.ulp(0.0), 1);
    RBits("Math.scale(1, -150)", Math.scale(1.0, -150), 0);
    Bits("MathL.scale(1, -2000)", MathL.scale(1.0D0, -2000), 0);
    Code("no error from a scale to zero", 0)
  END Denormals;

  PROCEDURE Neighbours;
  BEGIN
    Bits("MathL.succ(0)", MathL.succ(0.0D0), 1);
    Bits("MathL.pred(0)", MathL.pred(0.0D0), -9223372036854775807);
    Bits("MathL.succ(1)", MathL.succ(1.0D0), 4607182418800017409);
    Bits("MathL.pred(1)", MathL.pred(1.0D0), 4607182418800017407);
    Bits("MathL.succ(-1.5)", MathL.succ(-1.5D0), -4613937818241073153);
    Bits("MathL.pred(-1)", MathL.pred(-1.0D0), -4616189618054758399);
    RBits("Math.succ(0)", Math.succ(0.0), 1);
    RBits("Math.pred(0)", Math.pred(0.0), -2147483647);
    RBits("Math.pred(1)", Math.pred(1.0), 1065353215);
    RBits("Math.succ(-1.5)", Math.succ(-1.5), -1077936129);
    (* nothing above the largest number *)
    Bits("MathL.succ(large)", MathL.succ(MathL.large), 9218868437227405311);
    Code("MathL.succ(large)", Math.Overflow);
    Bits("MathL.pred(-large)", MathL.pred(-MathL.large), -4503599627370497);
    Code("MathL.pred(-large)", Math.Overflow);
    RBits("Math.succ(large)", Math.succ(Math.large), 2139095039);
    Code("Math.succ(large)", Math.Overflow)
  END Neighbours;

  PROCEDURE SinCos;
  BEGIN
    MathL.sincos(3.0D0, s, c);
    IF (s < 0.14D0) OR (s > 0.15D0) OR (c > -0.98D0) THEN Fail("MathL.sincos(3)") END;
    MathL.sincos(-2.0D0, s, c);
    IF (s > -0.9D0) OR (c > -0.4D0) OR (c < -0.5D0) THEN Fail("MathL.sincos(-2)") END;
    Math.sincos(3.0, rs, rc);
    IF (rs < 0.14) OR (rs > 0.15) OR (rc > -0.98) THEN Fail("Math.sincos(3)") END
  END SinCos;

  PROCEDURE Errors;
  BEGIN
    (* the range of the type *)
    x := MathL.exp(-800.0D0);
    Bits("MathL.exp(-800)", x, 0); Code("MathL.exp(-800)", Math.Underflow);
    x := MathL.exp(-740.0D0);
    IF x = 0 THEN Fail("MathL.exp(-740) is a denormal") END;
    Code("MathL.exp(-740)", Math.NoError);
    x := MathL.exp(710.0D0);
    Bits("MathL.exp(710)", x, 9218868437227405311); Code("MathL.exp(710)", Math.Overflow);
    r := Math.exp(-100.0);
    IF r = 0 THEN Fail("Math.exp(-100) is a denormal") END;
    Code("Math.exp(-100)", Math.NoError);
    r := Math.exp(-110.0);
    RBits("Math.exp(-110)", r, 0); Code("Math.exp(-110)", Math.Underflow);
    x := MathL.power(2.0D0, -1080.0D0);
    Bits("MathL.power(2, -1080)", x, 0); Code("MathL.power(2, -1080)", Math.Underflow);
    x := MathL.power(2.0D0, 2000.0D0);
    Bits("MathL.power(2, 2000)", x, 9218868437227405311); Code("MathL.power(2, 2000)", Math.Overflow);
    x := MathL.power(0.0D0, 3.0D0);
    Bits("MathL.power(0, 3)", x, 0); Code("MathL.power(0, 3)", Math.NoError);
    x := MathL.power(0.0D0, -1.0D0);
    Bits("MathL.power(0, -1)", x, 9218868437227405311); Code("MathL.power(0, -1)", Math.IllegalPower);
    x := MathL.power(-2.0D0, 2.0D0);
    IF x # 4.0D0 THEN Fail("MathL.power(-2, 2) is the power of 2") END;
    Code("MathL.power(-2, 2)", Math.IllegalPower);
    x := MathL.ipower(-2.0D0, 1025);
    Bits("MathL.ipower(-2, 1025)", x, -4503599627370497); Code("MathL.ipower(-2, 1025)", Math.Overflow);
    x := MathL.ipower(0.0D0, -1);
    Bits("MathL.ipower(0, -1)", x, 9218868437227405311); Code("MathL.ipower(0, -1)", Math.Overflow);
    x := MathL.ipower(2.0D0, -1080);
    Bits("MathL.ipower(2, -1080)", x, 0); Code("MathL.ipower(2, -1080)", Math.NoError);
    x := MathL.scale(1.0D0, 2000);
    Bits("MathL.scale(1, 2000)", x, 9218868437227405311); Code("MathL.scale(1, 2000)", Math.Overflow);
    r := Math.scale(-1.0, 200);
    RBits("Math.scale(-1, 200)", r, -8388609); Code("Math.scale(-1, 200)", Math.Overflow);
    x := MathL.sinh(1000.0D0);
    Bits("MathL.sinh(1000)", x, 9218868437227405311); Code("MathL.sinh(1000)", Math.Overflow);
    x := MathL.cosh(-1000.0D0);
    Bits("MathL.cosh(-1000)", x, 9218868437227405311); Code("MathL.cosh(-1000)", Math.Overflow);
    x := MathL.sinh(-1000.0D0);
    Bits("MathL.sinh(-1000)", x, -4503599627370497); Code("MathL.sinh(-1000)", Math.Overflow);
    (* the domains *)
    x := MathL.log(8.0D0, 1.0D0);
    IF x > -1.0D300 THEN Fail("MathL.log(8, 1)") END;
    Code("MathL.log(8, 1)", Math.IllegalLogBase);
    x := MathL.log(-8.0D0, 2.0D0);
    IF x > -1.0D300 THEN Fail("MathL.log(-8, 2)") END;
    Code("MathL.log(-8, 2)", Math.IllegalLog);
    x := MathL.arctan2(0.0D0, 0.0D0);
    Bits("MathL.arctan2(0, 0)", x, 0); Code("MathL.arctan2(0, 0)", Math.IllegalTrig);
    x := MathL.arctanh(1.0D0);
    IF ABS(x - 18.714973875118524D0) > 1.0D-12 THEN Fail("MathL.arctanh(1)") END;
    Code("MathL.arctanh(1)", Math.IllegalHypInvTrig);
    x := MathL.arctanh(-2.0D0);
    IF ABS(x + 18.714973875118524D0) > 1.0D-12 THEN Fail("MathL.arctanh(-2)") END;
    Code("MathL.arctanh(-2)", Math.IllegalHypInvTrig);
    x := MathL.arctanh(0.5D0);
    IF ABS(x - 0.5493061443340548D0) > 1.0D-15 THEN Fail("MathL.arctanh(0.5)") END;
    Code("MathL.arctanh(0.5)", Math.NoError);
    r := Math.arctanh(1.0);
    IF ABS(r - 8.664339742098155) > 1.0E-5 THEN Fail("Math.arctanh(1)") END;
    Code("Math.arctanh(1)", Math.IllegalHypInvTrig);
    r := Math.log(8.0, 1.0);
    IF r > -1.0E30 THEN Fail("Math.log(8, 1)") END;
    Code("Math.log(8, 1)", Math.IllegalLogBase);
    (* an infinity has an exponent past the top *)
    x := MathL.large; x := x * 2;
    Same("MathL.exponent(infinity)", MathL.exponent(x), MathL.expoMax + 1);
    r := Math.large; r := r * 2;
    Same("Math.exponent(infinity)", Math.exponent(r), Math.expoMax + 1)
  END Errors;

  PROCEDURE Rounding;
  BEGIN
    Same("MathL.round(0.49999999999999994)", MathL.round(0.49999999999999994D0), 0);
    Same("MathL.round(-0.49999999999999994)", MathL.round(-0.49999999999999994D0), 0);
    Same("MathL.round(1D300)", MathL.round(1.0D300), MAX(LONGINT));
    Same("MathL.round(-1D300)", MathL.round(-1.0D300), MIN(LONGINT));
    Same("MathL.round(MAX(LONGINT) - 0.5)", MathL.round(MAX(LONGINT) - 0.5D0), MAX(LONGINT));
    Same("MathL.round(MAX(LONGINT) - 0.75)", MathL.round(MAX(LONGINT) - 0.75D0), MAX(LONGINT) - 1);
    Same("MathL.round(-MAX(LONGINT) - 0.5)", MathL.round(-MAX(LONGINT) - 0.5D0), MIN(LONGINT));
    Same("MathL.round(-MAX(LONGINT) - 0.25)", MathL.round(-MAX(LONGINT) - 0.25D0), -MAX(LONGINT));
    Same("MathL.round(-MAX(LONGINT) + 0.5)", MathL.round(-MAX(LONGINT) + 0.5D0), -MAX(LONGINT));
    Same("Math.round(1E30)", Math.round(1.0E30), MAX(LONGINT));
    Same("Math.round(-1E30)", Math.round(-1.0E30), MIN(LONGINT));
    Same("Math.round(1E9)", Math.round(1.0E9), 1000000000);
    Same("Math.round(-7.5)", Math.round(-7.5), -8);
    Same("Math.round(7.5)", Math.round(7.5), 8)
  END Rounding;

BEGIN
  failures := 0;
  Constants;
  Exact;
  Denormals;
  Neighbours;
  SinCos;
  Errors;
  Rounding;
  IF failures = 0 THEN Out.String("all extra checks passed") ELSE Out.Int(failures, 0); Out.String(" checks failed") END;
  Out.Ln
END mathextra.
