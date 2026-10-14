MODULE vaxmathextra;
  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.15, proposal 5): rtl/vax/Math.Mod and MathL.Mod where VAX/VMS
     differs from LLVM, in place of llvm-math-extra, which checks IEEE's bit
     patterns, denormals and infinities. Bit patterns are F_floating's and
     G_floating's as SYSTEM.VAL reads them, the first word in memory, which
     holds the sign and the exponent, being the low word; they were computed
     with Python's fractions from the exact values. The other values are
     Python's math module's. *)
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

  (* got within a relative 1.0D-14 of want *)
  PROCEDURE Near(name: ARRAY OF CHAR; got, want: LONGREAL);
  BEGIN IF ABS(got - want) > 1.0D-14 * ABS(want) THEN Fail(name) END END Near;

  (* the same within 1.0E-6, for a REAL *)
  PROCEDURE RNear(name: ARRAY OF CHAR; got: REAL; want: LONGREAL);
  BEGIN IF ABS(got - want) > 1.0D-6 * ABS(want) THEN Fail(name) END END RNear;

  PROCEDURE Code(name: ARRAY OF CHAR; want: INTEGER);
  BEGIN
    IF Math.err # want THEN Fail(name); Out.Int(Math.err, 0); Out.Ln END;
    Math.ClearError
  END Code;

  PROCEDURE Constants;
  BEGIN
    Bits("MathL.large", MathL.large, -32769);
    Bits("MathL.small", MathL.small, 16);
    Same("MathL.expoMax", MathL.expoMax, 1022);
    Same("MathL.expoMin", MathL.expoMin, -1024);
    RBits("Math.large", Math.large, -32769);
    RBits("Math.small", Math.small, 128);
    Same("Math.expoMax", Math.expoMax, 126);
    Same("Math.expoMin", Math.expoMin, -128)
  END Constants;

  PROCEDURE LargeArguments;
  BEGIN
    (* MTH$ reduces a large argument accurately *)
    Near("MathL.sin(2^60)", MathL.sin(MathL.scale(1.0D0, 60)), -0.8306492176372546D0);
    Near("MathL.sin(1D300)", MathL.sin(1.0D300), -0.8178819121159085D0);
    Near("MathL.cos(1D22)", MathL.cos(1.0D22), 0.523214785395139D0);
    Near("MathL.tan(pi/2)", MathL.tan(1.5707963267948966D0), 1.633123935319537D16);
    RNear("Math.sin(2^40)", Math.sin(Math.scale(1.0, 40)), -0.40570501153282873D0);
    RNear("Math.sin(1E30)", Math.sin(1.0E30), -0.7911634385219837D0)
  END LargeArguments;

  PROCEDURE Properties;
  BEGIN
    (* the ends of the range *)
    Same("MathL.exponent(large)", MathL.exponent(MathL.large), 1022);
    Same("MathL.exponent(small)", MathL.exponent(MathL.small), -1024);
    Bits("MathL.fraction(large)", MathL.fraction(MathL.large), -49121);
    Same("Math.exponent(large)", Math.exponent(Math.large), 126);
    Same("Math.exponent(small)", Math.exponent(Math.small), -128);
    RBits("Math.fraction(large)", Math.fraction(Math.large), -48897);
    RBits("Math.fraction(-small)", Math.fraction(-Math.small), 49280);
    (* scale is exact within the range, 0 below it, +-large and an
       Overflow above it *)
    Bits("MathL.scale(1, -1024)", MathL.scale(1.0D0, -1024), 16); Code("MathL.scale(1, -1024)", Math.NoError);
    Bits("MathL.scale(1, -1025)", MathL.scale(1.0D0, -1025), 0); Code("MathL.scale(1, -1025)", Math.NoError);
    Bits("MathL.scale(1, 1023)", MathL.scale(1.0D0, 1023), -32769); Code("MathL.scale(1, 1023)", Math.Overflow);
    RBits("Math.scale(1, -128)", Math.scale(1.0, -128), 128); Code("Math.scale(1, -128)", Math.NoError);
    RBits("Math.scale(1, -129)", Math.scale(1.0, -129), 0); Code("Math.scale(1, -129)", Math.NoError);
    RBits("Math.scale(-1, 200)", Math.scale(-1.0, 200), -1); Code("Math.scale(-1, 200)", Math.Overflow);
    (* ulp, 0 where the unit is below the range *)
    Bits("MathL.ulp(1)", MathL.ulp(1.0D0), 15568);
    Bits("MathL.ulp(small)", MathL.ulp(MathL.small), 0);
    Bits("MathL.ulp(0)", MathL.ulp(0.0D0), 0);
    RBits("Math.ulp(1)", Math.ulp(1.0), 13568);
    RBits("Math.ulp(small)", Math.ulp(Math.small), 0)
  END Properties;

  PROCEDURE Neighbours;
  BEGIN
    (* no denormals: next to 0 is small *)
    Bits("MathL.succ(0)", MathL.succ(0.0D0), 16);
    Bits("MathL.pred(0)", MathL.pred(0.0D0), 32784);
    Bits("MathL.succ(-small)", MathL.succ(-MathL.small), 0);
    Bits("MathL.pred(small)", MathL.pred(MathL.small), 0);
    Bits("MathL.succ(small)", MathL.succ(MathL.small), 281474976710672);
    Bits("MathL.succ(1)", MathL.succ(1.0D0), 281474976727056);
    Bits("MathL.pred(1)", MathL.pred(1.0D0), -49137);
    Bits("MathL.succ(-1)", MathL.succ(-1.0D0), -16369);
    Bits("MathL.pred(-1)", MathL.pred(-1.0D0), 281474976759824);
    Bits("MathL.pred(large)", MathL.pred(MathL.large), -281474976743425);
    Code("MathL neighbours", Math.NoError);
    Bits("MathL.succ(large)", MathL.succ(MathL.large), -32769); Code("MathL.succ(large)", Math.Overflow);
    Bits("MathL.pred(-large)", MathL.pred(-MathL.large), -1); Code("MathL.pred(-large)", Math.Overflow);
    RBits("Math.succ(0)", Math.succ(0.0), 128);
    RBits("Math.pred(0)", Math.pred(0.0), 32896);
    RBits("Math.succ(-small)", Math.succ(-Math.small), 0);
    RBits("Math.pred(small)", Math.pred(Math.small), 0);
    RBits("Math.succ(small)", Math.succ(Math.small), 65664);
    RBits("Math.succ(1)", Math.succ(1.0), 82048);
    RBits("Math.pred(1)", Math.pred(1.0), -49025);
    RBits("Math.succ(-1)", Math.succ(-1.0), -16257);
    RBits("Math.pred(-1)", Math.pred(-1.0), 114816);
    RBits("Math.pred(large)", Math.pred(Math.large), -98305);
    Code("Math neighbours", Math.NoError);
    RBits("Math.succ(large)", Math.succ(Math.large), -32769); Code("Math.succ(large)", Math.Overflow);
    RBits("Math.pred(-large)", Math.pred(-Math.large), -1); Code("Math.pred(-large)", Math.Overflow)
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

  PROCEDURE Overflows;
  BEGIN
    (* what MTH$ and OTS$ signal comes back as an Overflow and +-large *)
    x := MathL.exp(710.0D0);
    Bits("MathL.exp(710)", x, -32769); Code("MathL.exp(710)", Math.Overflow);
    x := MathL.exp(-700.0D0);
    Near("MathL.exp(-700)", x, 9.85967654375977D-305); Code("MathL.exp(-700)", Math.NoError);
    x := MathL.exp(-720.0D0);
    Bits("MathL.exp(-720)", x, 0); Code("MathL.exp(-720)", Math.Underflow);
    r := Math.exp(89.0);
    RBits("Math.exp(89)", r, -32769); Code("Math.exp(89)", Math.Overflow);
    r := Math.exp(-88.0);
    RNear("Math.exp(-88)", r, 6.054601895401186D-39); Code("Math.exp(-88)", Math.NoError);
    r := Math.exp(-100.0);
    RBits("Math.exp(-100)", r, 0); Code("Math.exp(-100)", Math.Underflow);
    x := MathL.sinh(-1000.0D0);
    Bits("MathL.sinh(-1000)", x, -1); Code("MathL.sinh(-1000)", Math.Overflow);
    x := MathL.cosh(-1000.0D0);
    Bits("MathL.cosh(-1000)", x, -32769); Code("MathL.cosh(-1000)", Math.Overflow);
    r := Math.sinh(-100.0);
    RBits("Math.sinh(-100)", r, -1); Code("Math.sinh(-100)", Math.Overflow);
    r := Math.cosh(100.0);
    RBits("Math.cosh(100)", r, -32769); Code("Math.cosh(100)", Math.Overflow);
    x := MathL.power(2.0D0, 2000.0D0);
    Bits("MathL.power(2, 2000)", x, -32769); Code("MathL.power(2, 2000)", Math.Overflow);
    x := MathL.power(2.0D0, -1080.0D0);
    Bits("MathL.power(2, -1080)", x, 0); Code("MathL.power(2, -1080)", Math.Underflow);
    r := Math.power(10.0, 40.0);
    RBits("Math.power(10, 40)", r, -32769); Code("Math.power(10, 40)", Math.Overflow);
    r := Math.power(10.0, -40.0);
    RBits("Math.power(10, -40)", r, 0); Code("Math.power(10, -40)", Math.Underflow);
    x := MathL.power(0.0D0, -1.0D0);
    Bits("MathL.power(0, -1)", x, -32769); Code("MathL.power(0, -1)", Math.IllegalPower);
    x := MathL.ipower(-2.0D0, 1025);
    Bits("MathL.ipower(-2, 1025)", x, -1); Code("MathL.ipower(-2, 1025)", Math.Overflow);
    x := MathL.ipower(0.0D0, -1);
    Bits("MathL.ipower(0, -1)", x, -32769); Code("MathL.ipower(0, -1)", Math.Overflow);
    x := MathL.ipower(0.0D0, 0);
    IF x # 1 THEN Fail("MathL.ipower(0, 0)") END; Code("MathL.ipower(0, 0)", Math.NoError);
    x := MathL.ipower(2.0D0, -1080);
    Bits("MathL.ipower(2, -1080)", x, 0); Code("MathL.ipower(2, -1080)", Math.NoError);
    r := Math.ipower(-2.0, 129);
    RBits("Math.ipower(-2, 129)", r, -1); Code("Math.ipower(-2, 129)", Math.Overflow);
    r := Math.ipower(2.0, -200);
    RBits("Math.ipower(2, -200)", r, 0); Code("Math.ipower(2, -200)", Math.NoError);
    r := Math.ipower(0.5, -200);
    RBits("Math.ipower(0.5, -200)", r, -32769); Code("Math.ipower(0.5, -200)", Math.Overflow)
  END Overflows;

  PROCEDURE Domains;
  BEGIN
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
    r := Math.arctanh(1.0);
    IF ABS(r - 8.664339742098155) > 1.0E-5 THEN Fail("Math.arctanh(1)") END;
    Code("Math.arctanh(1)", Math.IllegalHypInvTrig);
    r := Math.ln(0.0);
    IF r > -1.0E30 THEN Fail("Math.ln(0)") END;
    Code("Math.ln(0)", Math.IllegalLog)
  END Domains;

  PROCEDURE Hyperbolic;
  BEGIN
    (* arcsinh and arccosh, which MTH$ does not have *)
    Near("MathL.arcsinh(1D-10)", MathL.arcsinh(1.0D-10), 1.0D-10);
    Near("MathL.arcsinh(0.3)", MathL.arcsinh(0.3D0), 0.29567304756342244D0);
    Near("MathL.arcsinh(1D5)", MathL.arcsinh(1.0D5), 12.206072645555174D0);
    Near("MathL.arcsinh(-1D20)", MathL.arcsinh(-1.0D20), -46.74484904044086D0);
    Near("MathL.arcsinh(1D300)", MathL.arcsinh(1.0D300), 691.4686750787737D0);
    Near("MathL.arccosh(1 + 2^-52)", MathL.arccosh(1.0D0 + MathL.ulp(1.0D0)), 2.1073424255447014D-8);
    Near("MathL.arccosh(1.5)", MathL.arccosh(1.5D0), 0.9624236501192069D0);
    Near("MathL.arccosh(1D5)", MathL.arccosh(1.0D5), 12.206072645505174D0);
    Near("MathL.arccosh(1D300)", MathL.arccosh(1.0D300), 691.4686750787737D0);
    RNear("Math.arcsinh(1E-10)", Math.arcsinh(1.0E-10), 1.0D-10);
    RNear("Math.arcsinh(0.3)", Math.arcsinh(0.3), 0.29567304756342244D0);
    RNear("Math.arcsinh(1E5)", Math.arcsinh(1.0E5), 12.206072645555174D0);
    RNear("Math.arcsinh(-1E20)", Math.arcsinh(-1.0E20), -46.74484904044086D0);
    RNear("Math.arccosh(1 + 2^-23)", Math.arccosh(1.0 + Math.ulp(1.0)), 0.0004882812451493617D0);
    RNear("Math.arccosh(1.5)", Math.arccosh(1.5), 0.9624236501192069D0);
    RNear("Math.arccosh(1E5)", Math.arccosh(1.0E5), 12.206072645505174D0);
    Code("arcsinh and arccosh", Math.NoError)
  END Hyperbolic;

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
  LargeArguments;
  Properties;
  Neighbours;
  SinCos;
  Overflows;
  Domains;
  Hyperbolic;
  Rounding;
  IF failures = 0 THEN Out.String("all VAX Math and MathL checks passed") ELSE Out.Int(failures, 0); Out.String(" checks failed") END;
  Out.Ln
END vaxmathextra.
