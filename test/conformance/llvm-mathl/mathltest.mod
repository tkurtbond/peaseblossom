MODULE mathltest;
  (* PLAN.md Phase 10 step 6: rtl/llvm/MathL.Mod - every function of the
     interface, against the exact value (from Python's math module, to
     double precision) within a relative 1.0D-12; test.sh runs this same
     source under voc and under poc and requires the same output, so both
     compilers' MathL must agree with the mathematics, whatever their last
     bit. Only errors that voc reports the same way are exercised here
     (llvm-math-extra has the rest). The expected values were computed
     with Python's math module and pasted in. *)
  IMPORT MathL, Math, Out;

  VAR
    failures, handled: INTEGER; lastCode: INTEGER;

  PROCEDURE Near(name: ARRAY OF CHAR; got, want: LONGREAL);
    VAR diff, bound: LONGREAL;
  BEGIN
    diff := ABS(got - want);
    bound := 1.0D-12 * ABS(want);
    IF bound < 1.0D-12 THEN bound := 1.0D-12 END;
    IF diff > bound THEN
      INC(failures);
      Out.String("FAIL "); Out.String(name); Out.Ln
    END
  END Near;

  PROCEDURE Exactly(name: ARRAY OF CHAR; got, want: LONGINT);
  BEGIN
    IF got # want THEN
      INC(failures);
      Out.String("FAIL "); Out.String(name); Out.Ln
    END
  END Exactly;

  PROCEDURE Error(name: ARRAY OF CHAR; got, want: INTEGER);
  BEGIN
    IF got # want THEN
      INC(failures);
      Out.String("FAIL error code of "); Out.String(name); Out.String(": ");
      Out.Int(got, 0); Out.Ln
    END
  END Error;

  PROCEDURE Handler(errno: INTEGER);
  BEGIN
    INC(handled); lastCode := errno
  END Handler;

  PROCEDURE Values;
  BEGIN
    Near("sqrt(2)", MathL.sqrt(2.0D0), 1.4142135623730951D0);
    Near("sqrt(0)", MathL.sqrt(0.0D0), 0.0D0);
    Near("sqrt(10000)", MathL.sqrt(10000.0D0), 100.0D0);
    Near("sqrt(0.25)", MathL.sqrt(0.25D0), 0.5D0);
    Near("sin(0.5)", MathL.sin(0.5D0), 0.479425538604203D0);
    Near("sin(-2)", MathL.sin(-2.0D0), -0.9092974268256817D0);
    Near("sin(1)", MathL.sin(1.0D0), 0.8414709848078965D0);
    Near("sin(0)", MathL.sin(0.0D0), 0.0D0);
    Near("cos(0.5)", MathL.cos(0.5D0), 0.8775825618903728D0);
    Near("cos(3)", MathL.cos(3.0D0), -0.9899924966004454D0);
    Near("cos(1)", MathL.cos(1.0D0), 0.5403023058681398D0);
    Near("cos(0)", MathL.cos(0.0D0), 1.0D0);
    Near("tan(0.5)", MathL.tan(0.5D0), 0.5463024898437905D0);
    Near("tan(-1)", MathL.tan(-1.0D0), -1.5574077246549023D0);
    Near("arcsin(0.5)", MathL.arcsin(0.5D0), 0.5235987755982989D0);
    Near("arcsin(-0.75)", MathL.arcsin(-0.75D0), -0.848062078981481D0);
    Near("arccos(0.5)", MathL.arccos(0.5D0), 1.0471975511965979D0);
    Near("arccos(-0.25)", MathL.arccos(-0.25D0), 1.8234765819369754D0);
    Near("arctan(1)", MathL.arctan(1.0D0), 0.7853981633974483D0);
    Near("arctan(-3)", MathL.arctan(-3.0D0), -1.2490457723982544D0);
    Near("arctan(0.001)", MathL.arctan(0.001D0), 0.0009999996666668668D0);
    Near("exp(1)", MathL.exp(1.0D0), 2.718281828459045D0);
    Near("exp(-1)", MathL.exp(-1.0D0), 0.36787944117144233D0);
    Near("exp(10)", MathL.exp(10.0D0), 22026.465794806718D0);
    Near("exp(0)", MathL.exp(0.0D0), 1.0D0);
    Near("exp(0.001)", MathL.exp(0.001D0), 1.0010005001667084D0);
    Near("ln(2)", MathL.ln(2.0D0), 0.6931471805599453D0);
    Near("ln(10)", MathL.ln(10.0D0), 2.302585092994046D0);
    Near("ln(0.001)", MathL.ln(0.001D0), -6.907755278982137D0);
    Near("ln(1)", MathL.ln(1.0D0), 0.0D0);
    Near("sinh(1)", MathL.sinh(1.0D0), 1.1752011936438014D0);
    Near("sinh(-2)", MathL.sinh(-2.0D0), -3.626860407847019D0);
    Near("sinh(0.1)", MathL.sinh(0.1D0), 0.10016675001984403D0);
    Near("cosh(1)", MathL.cosh(1.0D0), 1.5430806348152437D0);
    Near("cosh(-2)", MathL.cosh(-2.0D0), 3.7621956910836314D0);
    Near("cosh(0)", MathL.cosh(0.0D0), 1.0D0);
    Near("tanh(0.5)", MathL.tanh(0.5D0), 0.46211715726000974D0);
    Near("tanh(-3)", MathL.tanh(-3.0D0), -0.9950547536867305D0);
    Near("tanh(0.01)", MathL.tanh(0.01D0), 0.00999966667999946D0);
    Near("arcsinh(1)", MathL.arcsinh(1.0D0), 0.881373587019543D0);
    Near("arcsinh(-5)", MathL.arcsinh(-5.0D0), -2.3124383412727525D0);
    Near("arcsinh(0.01)", MathL.arcsinh(0.01D0), 0.009999833340832888D0);
    Near("arccosh(2)", MathL.arccosh(2.0D0), 1.3169578969248168D0);
    Near("arccosh(1.5)", MathL.arccosh(1.5D0), 0.9624236501192069D0);
    Near("arccosh(1)", MathL.arccosh(1.0D0), 0.0D0);
    Near("arctanh(0.5)", MathL.arctanh(0.5D0), 0.5493061443340549D0);
    Near("arctanh(-0.9)", MathL.arctanh(-0.9D0), -1.4722194895832204D0);
    Near("arctanh(0.01)", MathL.arctanh(0.01D0), 0.010000333353334763D0);
    Near("arctan2(1, 1)", MathL.arctan2(1.0D0, 1.0D0), 0.7853981633974483D0);
    Near("arctan2(1, -1)", MathL.arctan2(1.0D0, -1.0D0), 2.356194490192345D0);
    Near("arctan2(-1, -1)", MathL.arctan2(-1.0D0, -1.0D0), -2.356194490192345D0);
    Near("arctan2(-1, 0)", MathL.arctan2(-1.0D0, 0.0D0), -1.5707963267948966D0);
    Near("arctan2(0, -1)", MathL.arctan2(0.0D0, -1.0D0), 3.141592653589793D0);
    Near("arctan2(3, 4)", MathL.arctan2(3.0D0, 4.0D0), 0.6435011087932844D0);
    Near("arctan2(-2, 5)", MathL.arctan2(-2.0D0, 5.0D0), -0.3805063771123649D0);
    Near("log(100, 10)", MathL.log(100.0D0, 10.0D0), 2.0D0);
    Near("log(8, 2)", MathL.log(8.0D0, 2.0D0), 3.0D0);
    Near("log(5, 3)", MathL.log(5.0D0, 3.0D0), 1.4649735207179269D0);
    Near("log(0.5, 2)", MathL.log(0.5D0, 2.0D0), -1.0D0);
    Near("power(2, 10)", MathL.power(2.0D0, 10.0D0), 1024.0D0);
    Near("power(2, 0.5)", MathL.power(2.0D0, 0.5D0), 1.4142135623730951D0);
    Near("power(10, -3)", MathL.power(10.0D0, -3.0D0), 0.001D0);
    Near("power(9, 0.5)", MathL.power(9.0D0, 0.5D0), 3.0D0);
    Near("power(1.5, 2.5)", MathL.power(1.5D0, 2.5D0), 2.7556759606310752D0);
  END Values;

  PROCEDURE Properties;
    VAR s, c: LONGREAL;
  BEGIN
    Exactly("exponent(8)", MathL.exponent(8.0D0), 3);
    Exactly("exponent(0.75)", MathL.exponent(0.75D0), -1);
    Exactly("exponent(1)", MathL.exponent(1.0D0), 0);
    Exactly("exponent(1000)", MathL.exponent(1000.0D0), 9);
    Exactly("exponent(-0.1)", MathL.exponent(-0.1D0), -4);
    Exactly("exponent(0)", MathL.exponent(0.0D0), 0);
    Near("fraction(8)", MathL.fraction(8.0D0), 1.0D0);
    Near("fraction(0.75)", MathL.fraction(0.75D0), 1.5D0);
    Near("fraction(-12)", MathL.fraction(-12.0D0), -1.5D0);
    Near("fraction(0)", MathL.fraction(0.0D0), 0.0D0);
    Near("scale(1.5, 3)", MathL.scale(1.5D0, 3), 12.0D0);
    Near("scale(12, -3)", MathL.scale(12.0D0, -3), 1.5D0);
    Near("scale(-3, 2)", MathL.scale(-3.0D0, 2), -12.0D0);
    Near("scale(0, 5)", MathL.scale(0.0D0, 5), 0.0D0);
    Near("sign(-2)", MathL.sign(-2.0D0), -1.0D0);
    Near("sign(3)", MathL.sign(3.0D0), 1.0D0);
    Near("ulp(1)", MathL.ulp(1.0D0), 2.220446049250313D-16);
    Near("ulp(8)", MathL.ulp(8.0D0), 1.7763568394002505D-15);
    Near("succ(1.5)", MathL.succ(1.5D0), 1.5000000000000002D0);
    Near("pred(1.5)", MathL.pred(1.5D0), 1.4999999999999998D0);
    Near("pred(2.5)", MathL.pred(2.5D0), 2.4999999999999996D0);
    IF MathL.fraction(8.0D0) # 1.0D0 THEN INC(failures); Out.String("FAIL exact fraction(8)"); Out.Ln END;
    IF MathL.scale(1.5D0, 3) # 12.0D0 THEN INC(failures); Out.String("FAIL exact scale(1.5, 3)"); Out.Ln END;
    MathL.sincos(0.5D0, s, c);
    Near("sincos sin", s, 0.479425538604203D0);
    Near("sincos cos", c, 0.8775825618903728D0);
    Near("ipower(2, 10)", MathL.ipower(2.0D0, 10), 1024.0D0);
    Near("ipower(3, -2)", MathL.ipower(3.0D0, -2), 0.1111111111111111D0);
    Near("ipower(-2, 3)", MathL.ipower(-2.0D0, 3), -8.0D0);
    Near("ipower(1.5, 5)", MathL.ipower(1.5D0, 5), 7.59375D0);
    Near("ipower(7, 0)", MathL.ipower(7.0D0, 0), 1.0D0);
    Near("ipower(0, 4)", MathL.ipower(0.0D0, 4), 0.0D0);
    Exactly("round(2.5)", MathL.round(2.5D0), 3);
    Exactly("round(-2.5)", MathL.round(-2.5D0), -3);
    Exactly("round(2.4)", MathL.round(2.4D0), 2);
    Exactly("round(-2.6)", MathL.round(-2.6D0), -3);
    Exactly("round(0)", MathL.round(0.0D0), 0);
    Exactly("round(1000.5)", MathL.round(1000.5D0), 1001);
    Exactly("round(-0.4)", MathL.round(-0.4D0), 0);
    Exactly("fcmp(1, 1.0000001, 1e-3)", MathL.fcmp(1.0D0, 1.0000001D0, 1.0D-3), 0);
    Exactly("fcmp(1, 2, 1e-3)", MathL.fcmp(1.0D0, 2.0D0, 1.0D-3), -1);
    Exactly("fcmp(3, 2, 1e-6)", MathL.fcmp(3.0D0, 2.0D0, 1.0D-6), 1);
    Exactly("fcmp(5, 5, 0)", MathL.fcmp(5.0D0, 5.0D0, 0.0D0), 0);
    IF MathL.IsRMathException() THEN INC(failures); Out.String("FAIL IsRMathException"); Out.Ln END
  END Properties;

  PROCEDURE Constants;
  BEGIN
    Near("pi", MathL.pi, 3.141592653589793D0);
    Near("e", MathL.e, 2.718281828459045D0);
    Exactly("places", MathL.places, 53);
    Exactly("expoMax", MathL.expoMax, 1023);
    Exactly("expoMin", MathL.expoMin, -1022);
    IF MathL.large < 1.0D300 THEN INC(failures); Out.String("FAIL large"); Out.Ln END;
    IF (MathL.small <= 0) OR (MathL.small > 1.0D-300) THEN INC(failures); Out.String("FAIL small"); Out.Ln END
  END Constants;

  PROCEDURE Errors;
    VAR x: LONGREAL;
  BEGIN
    Math.ClearError; x := MathL.sqrt(-4.0D0); Error("sqrt(-4)", Math.err, 1);
    Near("sqrt(-4)", x, 2.0);
    Math.ClearError; x := MathL.ln(0.0D0); Error("ln(0)", Math.err, 2);
    IF x > -1.0E30 THEN INC(failures); Out.String("FAIL ln(0) value"); Out.Ln END;
    Math.ClearError; x := MathL.ln(-1.0D0); Error("ln(-1)", Math.err, 2);
    Math.ClearError; x := MathL.arcsin(2.0D0); Error("arcsin(2)", Math.err, 7);
    IF x < 1.0E30 THEN INC(failures); Out.String("FAIL arcsin(2) value"); Out.Ln END;
    Math.ClearError; x := MathL.arccos(-1.5D0); Error("arccos(-1.5)", Math.err, 7);
    Math.ClearError; x := MathL.log(5.0D0, -1.0D0); Error("log(5, -1)", Math.err, 5);
    Math.ClearError; x := MathL.arccosh(0.5D0); Error("arccosh(0.5)", Math.err, 9);
    Near("arccosh(0.5)", x, 0.0);
    Math.ClearError; x := MathL.exp(1000.0D0); Error("exp(1000)", Math.err, 3);
    IF x < 1.0E30 THEN INC(failures); Out.String("FAIL exp(1000) value"); Out.Ln END;
    Math.ClearError; x := MathL.exp(1.0D0); Error("exp(1)", Math.err, 0);
    Math.ClearError; x := MathL.ln(1.0D0); Error("ln(1)", Math.err, 0);
    Math.ClearError; x := MathL.sqrt(4.0D0); Error("sqrt(4)", Math.err, 0);
    Math.ClearError; x := MathL.power(-2.0D0, 2.0D0); Error("power(-2, 2)", Math.err, 4);
    Math.ClearError; x := MathL.sqrt(4.0D0); Error("sqrt(4) again", Math.err, 0);
    (* an installed handler gets every code; a return from it goes on *)
    Math.ErrorHandler := Handler; handled := 0; lastCode := 0;
    x := MathL.ln(-1.0D0); x := MathL.sqrt(-1.0D0);
    Exactly("handler calls", handled, 2); Exactly("handler code", lastCode, 1);
    Near("sqrt(-1) after handler", x, 1.0)
  END Errors;

BEGIN
  failures := 0;
  Values;
  Properties;
  Constants;
  Errors;
  IF failures = 0 THEN Out.String("all MathL checks passed") ELSE Out.Int(failures, 0); Out.String(" checks failed") END;
  Out.Ln
END mathltest.
