MODULE mathtest;
  (* PLAN.md Phase 10 step 6: rtl/llvm/Math.Mod - every function of the
     interface, against the exact value (from Python's math module, to
     double precision) within a relative 1.0E-5; test.sh runs this same
     source under voc and under poc and requires the same output, so both
     compilers' Math must agree with the mathematics, whatever their last
     bit. Only errors that voc reports the same way are exercised here
     (llvm-math-extra has the rest). The expected values were computed
     with Python's math module and pasted in. *)
  IMPORT Math, Out;

  VAR
    failures, handled: INTEGER; lastCode: INTEGER;

  PROCEDURE Near(name: ARRAY OF CHAR; got, want: LONGREAL);
    VAR diff, bound: LONGREAL;
  BEGIN
    diff := ABS(got - want);
    bound := 1.0E-5 * ABS(want);
    IF bound < 1.0E-5 THEN bound := 1.0E-5 END;
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
    Near("sqrt(2)", Math.sqrt(2.0), 1.4142135623730951);
    Near("sqrt(0)", Math.sqrt(0.0), 0.0);
    Near("sqrt(10000)", Math.sqrt(10000.0), 100.0);
    Near("sqrt(0.25)", Math.sqrt(0.25), 0.5);
    Near("sin(0.5)", Math.sin(0.5), 0.479425538604203);
    Near("sin(-2)", Math.sin(-2.0), -0.9092974268256817);
    Near("sin(1)", Math.sin(1.0), 0.8414709848078965);
    Near("sin(0)", Math.sin(0.0), 0.0);
    Near("cos(0.5)", Math.cos(0.5), 0.8775825618903728);
    Near("cos(3)", Math.cos(3.0), -0.9899924966004454);
    Near("cos(1)", Math.cos(1.0), 0.5403023058681398);
    Near("cos(0)", Math.cos(0.0), 1.0);
    Near("tan(0.5)", Math.tan(0.5), 0.5463024898437905);
    Near("tan(-1)", Math.tan(-1.0), -1.5574077246549023);
    Near("arcsin(0.5)", Math.arcsin(0.5), 0.5235987755982989);
    Near("arcsin(-0.75)", Math.arcsin(-0.75), -0.848062078981481);
    Near("arccos(0.5)", Math.arccos(0.5), 1.0471975511965979);
    Near("arccos(-0.25)", Math.arccos(-0.25), 1.8234765819369754);
    Near("arctan(1)", Math.arctan(1.0), 0.7853981633974483);
    Near("arctan(-3)", Math.arctan(-3.0), -1.2490457723982544);
    Near("arctan(0.001)", Math.arctan(0.001), 0.0009999996666668668);
    Near("exp(1)", Math.exp(1.0), 2.718281828459045);
    Near("exp(-1)", Math.exp(-1.0), 0.36787944117144233);
    Near("exp(10)", Math.exp(10.0), 22026.465794806718);
    Near("exp(0)", Math.exp(0.0), 1.0);
    Near("exp(0.001)", Math.exp(0.001), 1.0010005001667084);
    Near("ln(2)", Math.ln(2.0), 0.6931471805599453);
    Near("ln(10)", Math.ln(10.0), 2.302585092994046);
    Near("ln(0.001)", Math.ln(0.001), -6.907755278982137);
    Near("ln(1)", Math.ln(1.0), 0.0);
    Near("sinh(1)", Math.sinh(1.0), 1.1752011936438014);
    Near("sinh(-2)", Math.sinh(-2.0), -3.626860407847019);
    Near("sinh(0.1)", Math.sinh(0.1), 0.10016675001984403);
    Near("cosh(1)", Math.cosh(1.0), 1.5430806348152437);
    Near("cosh(-2)", Math.cosh(-2.0), 3.7621956910836314);
    Near("cosh(0)", Math.cosh(0.0), 1.0);
    Near("tanh(0.5)", Math.tanh(0.5), 0.46211715726000974);
    Near("tanh(-3)", Math.tanh(-3.0), -0.9950547536867305);
    Near("tanh(0.01)", Math.tanh(0.01), 0.00999966667999946);
    Near("arcsinh(1)", Math.arcsinh(1.0), 0.881373587019543);
    Near("arcsinh(-5)", Math.arcsinh(-5.0), -2.3124383412727525);
    Near("arcsinh(0.01)", Math.arcsinh(0.01), 0.009999833340832888);
    Near("arccosh(2)", Math.arccosh(2.0), 1.3169578969248168);
    Near("arccosh(1.5)", Math.arccosh(1.5), 0.9624236501192069);
    Near("arccosh(1)", Math.arccosh(1.0), 0.0);
    Near("arctanh(0.5)", Math.arctanh(0.5), 0.5493061443340549);
    Near("arctanh(-0.9)", Math.arctanh(-0.9), -1.4722194895832204);
    Near("arctanh(0.01)", Math.arctanh(0.01), 0.010000333353334763);
    Near("arctan2(1, 1)", Math.arctan2(1.0, 1.0), 0.7853981633974483);
    Near("arctan2(1, -1)", Math.arctan2(1.0, -1.0), 2.356194490192345);
    Near("arctan2(-1, -1)", Math.arctan2(-1.0, -1.0), -2.356194490192345);
    Near("arctan2(-1, 0)", Math.arctan2(-1.0, 0.0), -1.5707963267948966);
    Near("arctan2(0, -1)", Math.arctan2(0.0, -1.0), 3.141592653589793);
    Near("arctan2(3, 4)", Math.arctan2(3.0, 4.0), 0.6435011087932844);
    Near("arctan2(-2, 5)", Math.arctan2(-2.0, 5.0), -0.3805063771123649);
    Near("log(100, 10)", Math.log(100.0, 10.0), 2.0);
    Near("log(8, 2)", Math.log(8.0, 2.0), 3.0);
    Near("log(5, 3)", Math.log(5.0, 3.0), 1.4649735207179269);
    Near("log(0.5, 2)", Math.log(0.5, 2.0), -1.0);
    Near("power(2, 10)", Math.power(2.0, 10.0), 1024.0);
    Near("power(2, 0.5)", Math.power(2.0, 0.5), 1.4142135623730951);
    Near("power(10, -3)", Math.power(10.0, -3.0), 0.001);
    Near("power(0, 3)", Math.power(0.0, 3.0), 0.0);
    Near("power(9, 0.5)", Math.power(9.0, 0.5), 3.0);
    Near("power(1.5, 2.5)", Math.power(1.5, 2.5), 2.7556759606310752);
  END Values;

  PROCEDURE Properties;
    VAR s, c: REAL;
  BEGIN
    Exactly("exponent(8)", Math.exponent(8.0), 3);
    Exactly("exponent(0.75)", Math.exponent(0.75), -1);
    Exactly("exponent(1)", Math.exponent(1.0), 0);
    Exactly("exponent(1000)", Math.exponent(1000.0), 9);
    Exactly("exponent(-0.1)", Math.exponent(-0.1), -4);
    Exactly("exponent(0)", Math.exponent(0.0), 0);
    Near("fraction(8)", Math.fraction(8.0), 1.0);
    Near("fraction(0.75)", Math.fraction(0.75), 1.5);
    Near("fraction(-12)", Math.fraction(-12.0), -1.5);
    Near("fraction(0)", Math.fraction(0.0), 0.0);
    Near("scale(1.5, 3)", Math.scale(1.5, 3), 12.0);
    Near("scale(12, -3)", Math.scale(12.0, -3), 1.5);
    Near("scale(-3, 2)", Math.scale(-3.0, 2), -12.0);
    Near("scale(0, 5)", Math.scale(0.0, 5), 0.0);
    Near("sign(-2)", Math.sign(-2.0), -1.0);
    Near("sign(3)", Math.sign(3.0), 1.0);
    Near("ulp(1)", Math.ulp(1.0), 1.1920928955078125E-07);
    Near("ulp(8)", Math.ulp(8.0), 9.5367431640625E-07);
    Near("succ(1.5)", Math.succ(1.5), 1.5000001192092896);
    Near("pred(1.5)", Math.pred(1.5), 1.4999998807907104);
    Near("pred(2.5)", Math.pred(2.5), 2.499999761581421);
    IF Math.fraction(8.0) # 1.0 THEN INC(failures); Out.String("FAIL exact fraction(8)"); Out.Ln END;
    IF Math.scale(1.5, 3) # 12.0 THEN INC(failures); Out.String("FAIL exact scale(1.5, 3)"); Out.Ln END;
    Math.sincos(0.5, s, c);
    Near("sincos sin", s, 0.479425538604203);
    Near("sincos cos", c, 0.8775825618903728);
    Near("ipower(2, 10)", Math.ipower(2.0, 10), 1024.0);
    Near("ipower(3, -2)", Math.ipower(3.0, -2), 0.1111111111111111);
    Near("ipower(-2, 3)", Math.ipower(-2.0, 3), -8.0);
    Near("ipower(1.5, 5)", Math.ipower(1.5, 5), 7.59375);
    Near("ipower(7, 0)", Math.ipower(7.0, 0), 1.0);
    Near("ipower(0, 4)", Math.ipower(0.0, 4), 0.0);
    Exactly("round(2.5)", Math.round(2.5), 3);
    Exactly("round(-2.5)", Math.round(-2.5), -3);
    Exactly("round(2.4)", Math.round(2.4), 2);
    Exactly("round(-2.6)", Math.round(-2.6), -3);
    Exactly("round(0)", Math.round(0.0), 0);
    Exactly("round(1000.5)", Math.round(1000.5), 1001);
    Exactly("round(-0.4)", Math.round(-0.4), 0);
    Exactly("fcmp(1, 1.0000001, 1e-3)", Math.fcmp(1.0, 1.0000001, 1.0E-3), 0);
    Exactly("fcmp(1, 2, 1e-3)", Math.fcmp(1.0, 2.0, 1.0E-3), -1);
    Exactly("fcmp(3, 2, 1e-6)", Math.fcmp(3.0, 2.0, 1.0E-6), 1);
    Exactly("fcmp(5, 5, 0)", Math.fcmp(5.0, 5.0, 0.0), 0);
    IF Math.IsRMathException() THEN INC(failures); Out.String("FAIL IsRMathException"); Out.Ln END
  END Properties;

  PROCEDURE Constants;
  BEGIN
    Near("pi", Math.pi, 3.141592653589793);
    Near("e", Math.e, 2.718281828459045);
    Exactly("places", Math.places, 24);
    Exactly("expoMax", Math.expoMax, 127);
    Exactly("expoMin", Math.expoMin, -126);
    IF Math.large < 1.0E37 THEN INC(failures); Out.String("FAIL large"); Out.Ln END;
    IF (Math.small <= 0) OR (Math.small > 1.0E-37) THEN INC(failures); Out.String("FAIL small"); Out.Ln END
  END Constants;

  PROCEDURE Errors;
    VAR x: REAL;
  BEGIN
    Math.ClearError; x := Math.sqrt(-4.0); Error("sqrt(-4)", Math.err, 1);
    Near("sqrt(-4)", x, 2.0);
    Math.ClearError; x := Math.ln(0.0); Error("ln(0)", Math.err, 2);
    IF x > -1.0E30 THEN INC(failures); Out.String("FAIL ln(0) value"); Out.Ln END;
    Math.ClearError; x := Math.ln(-1.0); Error("ln(-1)", Math.err, 2);
    Math.ClearError; x := Math.arcsin(2.0); Error("arcsin(2)", Math.err, 7);
    IF x < 1.0E30 THEN INC(failures); Out.String("FAIL arcsin(2) value"); Out.Ln END;
    Math.ClearError; x := Math.arccos(-1.5); Error("arccos(-1.5)", Math.err, 7);
    Math.ClearError; x := Math.log(5.0, -1.0); Error("log(5, -1)", Math.err, 5);
    Math.ClearError; x := Math.arccosh(0.5); Error("arccosh(0.5)", Math.err, 9);
    Near("arccosh(0.5)", x, 0.0);
    Math.ClearError; x := Math.exp(1000.0); Error("exp(1000)", Math.err, 3);
    IF x < 1.0E30 THEN INC(failures); Out.String("FAIL exp(1000) value"); Out.Ln END;
    Math.ClearError; x := Math.exp(1.0); Error("exp(1)", Math.err, 0);
    Math.ClearError; x := Math.ln(1.0); Error("ln(1)", Math.err, 0);
    Math.ClearError; x := Math.sqrt(4.0); Error("sqrt(4)", Math.err, 0);
    Math.ClearError; x := Math.exp(-200.0); Error("exp(-200)", Math.err, 11);
    Near("exp(-200)", x, 0.0);
    Math.ClearError; x := Math.power(-2.0, 2.0); Error("power(-2, 2)", Math.err, 4);
    Near("power(-2, 2)", x, 4.0);
    Math.ClearError; x := Math.power(0.0, -1.0); Error("power(0, -1)", Math.err, 4);
    IF x < 1.0E30 THEN INC(failures); Out.String("FAIL power(0,-1) value"); Out.Ln END;
    Math.ClearError; x := Math.arctan2(0.0, 0.0); Error("arctan2(0, 0)", Math.err, 6);
    Near("arctan2(0, 0)", x, 0.0);
    Math.ClearError; x := Math.ipower(0.0, -1); Error("ipower(0, -1)", Math.err, 3);
    IF x < 1.0E30 THEN INC(failures); Out.String("FAIL ipower(0,-1) value"); Out.Ln END;
    (* an installed handler gets every code; a return from it goes on *)
    Math.ErrorHandler := Handler; handled := 0; lastCode := 0;
    x := Math.ln(-1.0); x := Math.sqrt(-1.0);
    Exactly("handler calls", handled, 2); Exactly("handler code", lastCode, 1);
    Near("sqrt(-1) after handler", x, 1.0)
  END Errors;

BEGIN
  failures := 0;
  Values;
  Properties;
  Constants;
  Errors;
  IF failures = 0 THEN Out.String("all Math checks passed") ELSE Out.Int(failures, 0); Out.String(" checks failed") END;
  Out.Ln
END mathtest.
