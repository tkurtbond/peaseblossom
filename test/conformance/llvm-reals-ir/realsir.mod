MODULE realsir;
  (* PLAN.md Phase 9 step 2's golden-IR fixture for REAL/LONGREAL: the
     exact instruction forms (fadd/fsub/fmul/fdiv, fneg, fcmp with its
     ordered predicates and "une" for #, sitofp/fpext/fptrunc, the
     bitcast-and-mask ABS, ENTIER's fptosi-and-correct) and every way a
     real immediate is spelled - a REAL numeral through an fptrunc
     instruction (LLVM 22 accepts neither a non-exact decimal `float`
     literal nor an fptrunc constant expression), a LONGREAL numeral
     verbatim, and a computed CONST as its own IEEE-754 bit pattern,
     including a REAL one rounded to single precision first, negative
     ones, and values near both ends of the exponent range (a
     subnormal, and a large power of two). Built from exact
     power-of-two arithmetic on purpose, so each bit pattern can be
     checked independently of ConstantEvaluator.ParseReal's own
     (not correctly rounded) numeral parsing; the .ll is also handed to
     clang for real at each word size. *)
  CONST
    lit = 0.1;
    wide = 0.1D0;
    negWide = -1.5D-3;
    negZero = -0.0;
    third = 1.0D0 / 3.0D0;
    negThird = -third;
    rthird = 1.0 / 3.0;
    two40 = 1099511627776.0D0;
    s40 = 1.0D0 / two40;
    s80 = s40 * s40;
    s160 = s80 * s80;
    s320 = s160 * s160;
    s640 = s320 * s320;
    subnormal = s640 * s320 * s80;
    big = 1.0D0 / s640 / s320 / s40;
  VAR
    fx: REAL;
    dx: LONGREAL;
    lx: LONGINT;

  PROCEDURE Forms(a: REAL; b: LONGREAL; n: INTEGER): LONGREAL;
    VAR t: LONGREAL;
  BEGIN
    t := a + b;
    t := t - n;
    t := t * (-b);
    t := t / 3;
    IF (a < 1.5) OR (b >= 2) OR (n # 0) OR (a = b) OR (a > b) OR (a <= b) THEN t := ABS(t) END;
    lx := ENTIER(t);
    fx := ABS(a) / n;
    fx := SHORT(t);
    dx := LONG(fx);
    RETURN t
  END Forms;

BEGIN
  fx := lit; dx := wide; dx := negWide; dx := negZero;
  dx := third; dx := negThird; fx := rthird;
  dx := subnormal; dx := big;
  dx := Forms(fx, dx, 2)
END realsir.
