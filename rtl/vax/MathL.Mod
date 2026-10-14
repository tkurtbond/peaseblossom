MODULE MathL;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.15): the Oakwood LONGREAL mathematics on VAX/VMS, the same
     functions as Math (see there for the error codes, what comes back with
     each, and how the module is made) on G_floating, with the interface
     of rtl/llvm/MathL, which is voc's: everything Math has except the
     error handler, whose ErrorHandler, err, ClearError and codes live in
     Math; a MathL function reports through Math.ErrorHandler.

     The functions are MTH$'s G_floating routines, and OTS$'s for a power,
     through PocRtl's POC_MATH. G_floating's first word in memory, the low
     word of the bits, holds the sign (bit 15), the exponent (11 bits from
     bit 4, excess 1024, the fraction being 0.1f) and the fraction's top 4
     bits; the next three words the rest of the fraction, most significant
     first. So small is 2^-1024, large 2^1023 less a unit, and in the
     convention 1 <= |fraction(x)| < 2, expoMin is -1024 and expoMax
     1022. *)

  IMPORT SYSTEM, Math;

  CONST
    (* pi and e; the number of bits in the fraction (with its leading 1); the
       largest number and the smallest one; the largest and smallest
       exponent *)
    pi* = 3.14159265358979323846D0;
    e* = 2.71828182845904523536D0;
    places* = 53;
    large* = MAX(LONGREAL);
    small* = 5.5626846462680035D-309; (* above 2^-1024, which MACRO rounds it to *)
    expoMax* = 1022;
    expoMin* = -1024;

    (* POC_MATH's numbers of the G routines *)
    Sqrt = 16; Sin = 17; Cos = 18; Tan = 19; Asin = 20; Acos = 21; Atan = 22;
    Exp = 23; Log = 24; Sinh = 25; Cosh = 26; Tanh = 27; Atanh = 28;
    Atan2 = 29; Power = 30; IntPower = 31;

    ln2 = 0.693147180559945309417D0;
    wordBase = 10000H;
    signBit = 8000H;
    bias = 1025; (* the exponent field of a number of exponent 0 *)

  VAR
    TanhMax: LONGREAL; (* what arctanh gives for a number at or beyond +-1 *)

  PROCEDURE ["VMS"] POC_MATH(function: SYSTEM.INT32; VAR x, y, result: LONGREAL): SYSTEM.INT32;
  PROCEDURE ["VMS", "POC_MATH"] POC_MATH_INT(function: SYSTEM.INT32; VAR x: LONGREAL; VAR n: SYSTEM.INT32; VAR result: LONGREAL): SYSTEM.INT32;

  (* Always FALSE: an error goes to the error handler, never to an exception
     (voc's interface keeps it from the ISO library). *)
  PROCEDURE IsRMathException*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END IsRMathException;

  (* result := the G routine function of x (and y); FALSE if it signalled *)
  PROCEDURE Call(function: SYSTEM.INT32; x, y: LONGREAL; VAR result: LONGREAL): BOOLEAN;
  BEGIN
    result := 0;
    RETURN ODD(POC_MATH(function, x, y, result))
  END Call;

  (* The function of x, a G routine that does not signal for it *)
  PROCEDURE Of(function: SYSTEM.INT32; x: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF Call(function, x, x, result) THEN END;
    RETURN result
  END Of;

  (* large, or -large if negative, after an Overflow *)
  PROCEDURE Overflowed(negative: BOOLEAN): LONGREAL;
  BEGIN
    Math.ErrorHandler(Math.Overflow);
    IF negative THEN RETURN -large ELSE RETURN large END
  END Overflowed;

  (* ---- real number properties ---- *)

  (* The exponent field of x, 0 for 0 *)
  PROCEDURE Field(x: LONGREAL): INTEGER;
  BEGIN
    RETURN SYSTEM.VAL(INTEGER, SYSTEM.VAL(HUGEINT, x) MOD wordBase DIV 16 MOD 2048)
  END Field;

  (* x, not 0, with the exponent field := field, 1..2047 *)
  PROCEDURE WithField(x: LONGREAL; field: LONGINT): LONGREAL;
  BEGIN
    RETURN SYSTEM.VAL(LONGREAL, SYSTEM.VAL(HUGEINT, x) + (field - Field(x)) * 16)
  END WithField;

  (* The exponent of x, the power of 2 with x = fraction(x) * 2^exponent(x):
     0 for 0. *)
  PROCEDURE exponent*(x: LONGREAL): INTEGER;
  BEGIN
    IF x = 0 THEN RETURN 0 END;
    RETURN Field(x) - bias
  END exponent;

  (* x without its exponent, 1 <= |fraction(x)| < 2; 0 comes back as it
     is. *)
  PROCEDURE fraction*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x = 0 THEN RETURN x END;
    RETURN WithField(x, bias)
  END fraction;

  (* -1 if x is negative, else 1 (0 included). *)
  PROCEDURE sign*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x < 0 THEN RETURN -1 ELSE RETURN 1 END
  END sign;

  (* x * 2^n, exactly: +-large and an Overflow above the range, 0 below
     it. *)
  PROCEDURE scale*(x: LONGREAL; n: INTEGER): LONGREAL;
    VAR expo: LONGINT;
  BEGIN
    IF x = 0 THEN RETURN x END;
    expo := LONG(exponent(x)) + n;
    IF expo > expoMax THEN RETURN Overflowed(x < 0)
    ELSIF expo < expoMin THEN RETURN 0
    END;
    RETURN WithField(x, expo + bias)
  END scale;

  (* The distance from |x| to the next larger number of x's exponent: one
     unit in the last place; 0 where that is below the range. *)
  PROCEDURE ulp*(x: LONGREAL): LONGREAL;
    VAR expo: INTEGER;
  BEGIN
    expo := exponent(x);
    IF x = 0 THEN expo := expoMin END;
    RETURN scale(1.0D0, expo - places + 1)
  END ulp;

  (* The number next to x, its magnitude one unit larger (step 1) or
     smaller (step -1): the magnitude's bits are the four words in the
     other order, without the sign *)
  PROCEDURE Step(x: LONGREAL; step: INTEGER): LONGREAL;
    VAR bits, first, magnitude: HUGEINT; k: INTEGER;
  BEGIN
    bits := SYSTEM.VAL(HUGEINT, x);
    first := bits MOD wordBase;
    magnitude := first MOD signBit;
    FOR k := 1 TO 3 DO
      bits := bits DIV wordBase;
      magnitude := magnitude * wordBase + bits MOD wordBase
    END;
    magnitude := magnitude + step;
    IF magnitude < ASH(1, places - 1) THEN RETURN 0 END; (* below small *)
    bits := 0;
    FOR k := 1 TO 3 DO
      bits := bits * wordBase + magnitude MOD wordBase;
      magnitude := magnitude DIV wordBase
    END;
    bits := bits * wordBase + first DIV signBit * signBit + magnitude;
    RETURN SYSTEM.VAL(LONGREAL, bits)
  END Step;

  (* The next number above x, pred the next below it. *)
  PROCEDURE succ*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x >= large THEN RETURN Overflowed(FALSE)
    ELSIF x = 0 THEN RETURN small
    ELSIF x > 0 THEN RETURN Step(x, 1)
    ELSE RETURN Step(x, -1)
    END
  END succ;

  PROCEDURE pred*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x <= -large THEN RETURN Overflowed(TRUE)
    ELSIF x = 0 THEN RETURN -small
    ELSIF x < 0 THEN RETURN Step(x, 1)
    ELSE RETURN Step(x, -1)
    END
  END pred;

  (* ---- elementary functions ---- *)

  (* The elementary functions, each with the error in Math's table: the
     square root, e^x, the natural logarithm, the logarithm to the base, and
     base^exp. *)
  PROCEDURE sqrt*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x < 0 THEN
      Math.ErrorHandler(Math.IllegalRoot);
      x := -x
    END;
    RETURN Of(Sqrt, x)
  END sqrt;

  PROCEDURE exp*(x: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF ~Call(Exp, x, x, result) THEN RETURN Overflowed(FALSE) END;
    IF result = 0 THEN Math.ErrorHandler(Math.Underflow) END;
    RETURN result
  END exp;

  PROCEDURE ln*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x <= 0 THEN
      Math.ErrorHandler(Math.IllegalLog);
      RETURN -large
    END;
    RETURN Of(Log, x)
  END ln;

  PROCEDURE log*(x, base: LONGREAL): LONGREAL;
  BEGIN
    IF (base <= 0) OR (base = 1) THEN
      Math.ErrorHandler(Math.IllegalLogBase);
      RETURN -large
    ELSIF x <= 0 THEN
      Math.ErrorHandler(Math.IllegalLog);
      RETURN -large
    END;
    RETURN Of(Log, x) / Of(Log, base)
  END log;

  PROCEDURE power*(base, exp: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF base <= 0 THEN
      IF base # 0 THEN
        Math.ErrorHandler(Math.IllegalPower);
        base := -base
      ELSIF exp > 0 THEN
        RETURN 0
      ELSE
        Math.ErrorHandler(Math.IllegalPower);
        RETURN large
      END
    END;
    IF ~Call(Power, base, exp, result) THEN RETURN Overflowed(FALSE) END;
    IF result = 0 THEN Math.ErrorHandler(Math.Underflow) END;
    RETURN result
  END power;

  (* x to the whole power base (despite its name, voc's, base is the
     exponent); x^0 is 1, 0^0 included. *)
  PROCEDURE ipower*(x: LONGREAL; base: INTEGER): LONGREAL;
    VAR n: SYSTEM.INT32; result: LONGREAL;
  BEGIN
    IF base = 0 THEN RETURN 1 END;
    n := base;
    result := 0;
    IF ~ODD(POC_MATH_INT(IntPower, x, n, result)) THEN
      RETURN Overflowed((x < 0) & ODD(base))
    END;
    RETURN result
  END ipower;

  (* The trigonometric functions, in radians. *)
  PROCEDURE sin*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Of(Sin, x)
  END sin;

  PROCEDURE cos*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Of(Cos, x)
  END cos;

  PROCEDURE tan*(x: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF ~Call(Tan, x, x, result) THEN RETURN Overflowed(FALSE) END;
    RETURN result
  END tan;

  (* The sine and cosine of x at once. *)
  PROCEDURE sincos*(x: LONGREAL; VAR Sin, Cos: LONGREAL);
  BEGIN
    Sin := sin(x);
    Cos := cos(x)
  END sincos;

  (* The inverse trigonometric functions, in radians: arcsin in -pi/2..pi/2,
     arccos in 0..pi, arctan in -pi/2..pi/2. *)
  PROCEDURE arcsin*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      Math.ErrorHandler(Math.IllegalInvTrig);
      RETURN large
    END;
    RETURN Of(Asin, x)
  END arcsin;

  PROCEDURE arccos*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      Math.ErrorHandler(Math.IllegalInvTrig);
      RETURN large
    END;
    RETURN Of(Acos, x)
  END arccos;

  PROCEDURE arctan*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Of(Atan, x)
  END arctan;

  (* The angle of the point (xd, xn) from the positive x-axis, in -pi..pi: the
     arctangent of xn / xd in the right quadrant. *)
  PROCEDURE arctan2*(xn, xd: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF (xn = 0) & (xd = 0) THEN
      Math.ErrorHandler(Math.IllegalTrig);
      RETURN 0
    END;
    IF Call(Atan2, xn, xd, result) THEN END;
    RETURN result
  END arctan2;

  (* The hyperbolic functions and their inverses. *)
  PROCEDURE sinh*(x: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF ~Call(Sinh, x, x, result) THEN RETURN Overflowed(x < 0) END;
    RETURN result
  END sinh;

  PROCEDURE cosh*(x: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    IF ~Call(Cosh, x, x, result) THEN RETURN Overflowed(FALSE) END;
    RETURN result
  END cosh;

  PROCEDURE tanh*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Of(Tanh, x)
  END tanh;

  (* ln(1 + u), u >= 0, without the loss of u's digits that adding it to 1
     would cost: ln(w) * u / (w - 1), w being 1 + u as rounded, which
     corrects for the rounding *)
  PROCEDURE LnOnePlus(u: LONGREAL): LONGREAL;
    VAR w: LONGREAL;
  BEGIN
    w := 1 + u;
    IF w = 1 THEN RETURN u END;
    RETURN Of(Log, w) * (u / (w - 1))
  END LnOnePlus;

  (* Beyond this, sqrt(x^2 +- 1) is |x| to every bit *)
  PROCEDURE Huge(x: LONGREAL): BOOLEAN;
  BEGIN
    RETURN x > 134217728.0D0 (* 2^(places DIV 2 + 1) *)
  END Huge;

  PROCEDURE arcsinh*(x: LONGREAL): LONGREAL;
    VAR a, result: LONGREAL;
  BEGIN
    a := ABS(x);
    IF Huge(a) THEN
      result := Of(Log, a) + ln2
    ELSIF a >= 0.5D0 THEN
      result := Of(Log, 2 * a + 1 / (Of(Sqrt, a * a + 1) + a))
    ELSE
      result := LnOnePlus(a + a * a / (1 + Of(Sqrt, 1 + a * a)))
    END;
    IF x < 0 THEN RETURN -result ELSE RETURN result END
  END arcsinh;

  PROCEDURE arccosh*(x: LONGREAL): LONGREAL;
    VAR t: LONGREAL;
  BEGIN
    IF x < 1 THEN
      Math.ErrorHandler(Math.IllegalHypInvTrig);
      RETURN 0
    END;
    IF Huge(x) THEN
      RETURN Of(Log, x) + ln2
    ELSIF x > 2 THEN
      RETURN Of(Log, 2 * x - 1 / (x + Of(Sqrt, x * x - 1)))
    END;
    t := x - 1;
    RETURN LnOnePlus(t + Of(Sqrt, 2 * t + t * t))
  END arccosh;

  PROCEDURE arctanh*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x >= 1) OR (x <= -1) THEN
      Math.ErrorHandler(Math.IllegalHypInvTrig);
      IF x < 0 THEN RETURN -TanhMax ELSE RETURN TanhMax END
    END;
    RETURN Of(Atanh, x)
  END arctanh;

  (* x rounded to the nearest whole number, halves away from zero; a number
     that rounds beyond LONGINT gives its largest or smallest value. *)
  PROCEDURE round*(x: LONGREAL): LONGINT;
    VAR n: LONGINT;
  BEGIN
    IF x >= MAX(LONGINT) - 0.5D0 THEN RETURN MAX(LONGINT)
    ELSIF x <= -MAX(LONGINT) - 0.5D0 THEN RETURN MIN(LONGINT)
    ELSIF x >= 0 THEN
      n := ENTIER(x);
      IF x - n >= 0.5D0 THEN INC(n) END;
      RETURN n
    ELSE
      n := ENTIER(-x);
      IF -x - n >= 0.5D0 THEN INC(n) END;
      RETURN -n
    END
  END round;

  (* -1, 0 or 1 as x is less than, approximately equal to, or greater than
     y, "approximately" meaning within epsilon times the larger power of 2
     at or below the larger of |x| and |y| (the GNU Scientific Library's
     gsl_fcmp, as voc's). *)
  PROCEDURE fcmp*(x, y, epsilon: LONGREAL): INTEGER;
    VAR larger, delta, difference: LONGREAL;
  BEGIN
    IF ABS(x) > ABS(y) THEN larger := x ELSE larger := y END;
    delta := 2.0D0 * epsilon * scale(1.0D0, exponent(larger));
    difference := x - y;
    IF difference > delta THEN RETURN 1
    ELSIF difference < -delta THEN RETURN -1
    ELSE RETURN 0
    END
  END fcmp;

BEGIN
  TanhMax := Of(Atanh, 1.0D0 - scale(1.0D0, -places))
END MathL.
