MODULE Math;

  (* PLAN.md Phase 17 step 3 (doc/developer/vax-macro32-backend.md, section
     19.15): the Oakwood REAL mathematics on VAX/VMS, with rtl/llvm/Math's
     interface, which is voc's, and its errors.

     The functions are MTH$'s F_floating routines, and OTS$'s for a power,
     called through PocRtl's POC_MATH (proposal 1). It returns 1, or the
     condition the routine signalled, with no message. Every domain error
     is checked here before the call, as on LLVM, so what comes back is an
     overflow: it reports Overflow and gives large, or -large where the
     true result is negative (proposal 2). MTH$ reduces a large argument
     to sin, cos or tan accurately. arcsinh and arccosh, which MTH$ does
     not have, are computed from ln and sqrt (proposal 3).

     The real-number properties (exponent, fraction, scale, ulp, succ,
     pred) are exact, from F_floating's fields: the first word in memory,
     the low word of the bits, holds the sign (bit 15) and the exponent
     (8 bits from bit 7, excess 128, the fraction being 0.1f), and the
     fraction's top 7 bits; the second word the rest of the fraction. F
     has no infinities, NaNs or denormals, so the smallest number is
     small, 2^-128, the largest 2^127 less a unit, and the constants say
     so (proposal 4): in the convention 1 <= |fraction(x)| < 2, expoMin
     is -128 and expoMax 126. scale below the range gives 0 with no error,
     as on LLVM, and so ulp gives 0 for a number whose unit is below it.

     Errors: a call that cannot give a real answer reports an error code
     through ErrorHandler and returns a fixed value, as in voc. The default
     handler stores the code in err (ClearError sets it back to NoError); a
     program may install its own, taking the code as its argument, and a
     handler that returns lets the function go on to its return value.
     MathL reports through this same handler. What is an error, and what
     comes back, is rtl/llvm/Math's table:

       ln(x), x <= 0        IllegalLog          -large
       log(x, base)         IllegalLogBase for base <= 0 or base = 1, or
                            IllegalLog for x <= 0                -large
       sqrt(x), x < 0       IllegalRoot         the root of -x
       exp(x)               Overflow            large
                            Underflow           0 (the result rounds to 0)
       power(b, e), b < 0   IllegalPower        the power of -b
       power(0, e), e <= 0  IllegalPower        large
       power(0, e), e > 0   0, no error
       power(b, e)          Overflow            large;  Underflow  0
       ipower(x, n)         Overflow            +-large (a result too large,
                                                or 0 to a negative power)
       arcsin/arccos(x), |x| > 1     IllegalInvTrig    large
       arctan2(0, 0)        IllegalTrig         0
       sinh, cosh           Overflow            +-large
       arccosh(x), x < 1    IllegalHypInvTrig   0
       arctanh(x), |x| >= 1 IllegalHypInvTrig   +-arctanh of the largest
                                                number below 1
       scale, succ, pred    Overflow            +-large

     Lengths and codes are INTEGER, and round is LONGINT, as on LLVM:
     round rounds halves away from zero and gives MAX(LONGINT) or
     MIN(LONGINT) for a number out of range. *)

  IMPORT SYSTEM;

  CONST
    (* pi and e; the number of bits in the fraction (with its leading 1); the
       largest number and the smallest one; the largest and smallest
       exponent *)
    pi* = 3.14159265358979323846;
    e* = 2.71828182845904523536;
    places* = 24;
    large* = MAX(REAL);
    small* = 2.9387359E-39;
    expoMax* = 126;
    expoMin* = -128;

    (* error codes *)
    NoError* = 0;
    IllegalRoot* = 1;
    IllegalLog* = 2;
    Overflow* = 3;
    IllegalPower* = 4;
    IllegalLogBase* = 5;
    IllegalTrig* = 6;
    IllegalInvTrig* = 7;
    HypInvTrigClipped* = 8;
    IllegalHypInvTrig* = 9;
    LossOfAccuracy* = 10;
    Underflow* = 11;

    (* POC_MATH's numbers of the F routines *)
    Sqrt = 0; Sin = 1; Cos = 2; Tan = 3; Asin = 4; Acos = 5; Atan = 6;
    Exp = 7; Log = 8; Sinh = 9; Cosh = 10; Tanh = 11; Atanh = 12;
    Atan2 = 13; Power = 14; IntPower = 15;

    ln2 = 0.693147180559945309417;
    wordBase = 10000H;
    signBit = 8000H;
    bias = 129; (* the exponent field of a number of exponent 0 *)

  VAR
    (* Called with the error code of a function that cannot give a real
       answer; at first a handler that stores the code in err. *)
    ErrorHandler*: PROCEDURE (errno: INTEGER);
    err-: INTEGER;
    TanhMax: REAL; (* what arctanh gives for a number at or beyond +-1 *)

  PROCEDURE ["VMS"] POC_MATH(function: SYSTEM.INT32; VAR x, y, result: REAL): SYSTEM.INT32;
  PROCEDURE ["VMS", "POC_MATH"] POC_MATH_INT(function: SYSTEM.INT32; VAR x: REAL; VAR n: SYSTEM.INT32; VAR result: REAL): SYSTEM.INT32;

  PROCEDURE DefaultErrorHandler(errno: INTEGER);
  BEGIN
    err := errno
  END DefaultErrorHandler;

  (* err := NoError *)
  PROCEDURE ClearError*;
  BEGIN
    err := NoError
  END ClearError;

  (* Always FALSE: an error goes to the error handler, never to an exception
     (voc's interface keeps it from the ISO library). *)
  PROCEDURE IsRMathException*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END IsRMathException;

  (* result := the F routine function of x (and y); FALSE if it signalled *)
  PROCEDURE Call(function: SYSTEM.INT32; x, y: REAL; VAR result: REAL): BOOLEAN;
  BEGIN
    result := 0;
    RETURN ODD(POC_MATH(function, x, y, result))
  END Call;

  (* The function of x, an F routine that does not signal for it *)
  PROCEDURE Of(function: SYSTEM.INT32; x: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF Call(function, x, x, result) THEN END;
    RETURN result
  END Of;

  (* large, or -large if negative, after an Overflow *)
  PROCEDURE Overflowed(negative: BOOLEAN): REAL;
  BEGIN
    ErrorHandler(Overflow);
    IF negative THEN RETURN -large ELSE RETURN large END
  END Overflowed;

  (* ---- real number properties ---- *)

  (* x's bits, sign-extended *)
  PROCEDURE Bits(x: REAL): HUGEINT;
  BEGIN
    RETURN SYSTEM.VAL(SYSTEM.INT32, x)
  END Bits;

  PROCEDURE FromBits(bits: HUGEINT): REAL;
  BEGIN
    RETURN SYSTEM.VAL(REAL, SYSTEM.VAL(SYSTEM.INT32, bits))
  END FromBits;

  (* The exponent field of x, 0 for 0 *)
  PROCEDURE Field(x: REAL): INTEGER;
  BEGIN
    RETURN SYSTEM.VAL(INTEGER, Bits(x) MOD wordBase DIV 128 MOD 256)
  END Field;

  (* x, not 0, with the exponent field := field, 1..255 *)
  PROCEDURE WithField(x: REAL; field: LONGINT): REAL;
  BEGIN
    RETURN FromBits(Bits(x) + (field - Field(x)) * 128)
  END WithField;

  (* The exponent of x, the power of 2 with x = fraction(x) * 2^exponent(x):
     0 for 0. *)
  PROCEDURE exponent*(x: REAL): INTEGER;
  BEGIN
    IF x = 0 THEN RETURN 0 END;
    RETURN Field(x) - bias
  END exponent;

  (* x without its exponent, 1 <= |fraction(x)| < 2; 0 comes back as it
     is. *)
  PROCEDURE fraction*(x: REAL): REAL;
  BEGIN
    IF x = 0 THEN RETURN x END;
    RETURN WithField(x, bias)
  END fraction;

  (* -1 if x is negative, else 1 (0 included). *)
  PROCEDURE sign*(x: REAL): REAL;
  BEGIN
    IF x < 0 THEN RETURN -1 ELSE RETURN 1 END
  END sign;

  (* x * 2^n, exactly: +-large and an Overflow above the range, 0 below
     it. *)
  PROCEDURE scale*(x: REAL; n: INTEGER): REAL;
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
  PROCEDURE ulp*(x: REAL): REAL;
    VAR expo: INTEGER;
  BEGIN
    expo := exponent(x);
    IF x = 0 THEN expo := expoMin END;
    RETURN scale(1.0, expo - places + 1)
  END ulp;

  (* The number next to x, its magnitude one unit larger (step 1) or
     smaller (step -1): the magnitude's bits are the words in the other
     order, without the sign *)
  PROCEDURE Step(x: REAL; step: INTEGER): REAL;
    VAR bits, first, magnitude: HUGEINT;
  BEGIN
    bits := Bits(x);
    first := bits MOD wordBase;
    magnitude := first MOD signBit * wordBase + bits DIV wordBase MOD wordBase + step;
    IF magnitude < ASH(1, places - 1) THEN RETURN 0 END; (* below small *)
    RETURN FromBits(magnitude MOD wordBase * wordBase + first DIV signBit * signBit + magnitude DIV wordBase)
  END Step;

  (* The next number above x, pred the next below it. *)
  PROCEDURE succ*(x: REAL): REAL;
  BEGIN
    IF x >= large THEN RETURN Overflowed(FALSE)
    ELSIF x = 0 THEN RETURN small
    ELSIF x > 0 THEN RETURN Step(x, 1)
    ELSE RETURN Step(x, -1)
    END
  END succ;

  PROCEDURE pred*(x: REAL): REAL;
  BEGIN
    IF x <= -large THEN RETURN Overflowed(TRUE)
    ELSIF x = 0 THEN RETURN -small
    ELSIF x < 0 THEN RETURN Step(x, 1)
    ELSE RETURN Step(x, -1)
    END
  END pred;

  (* ---- elementary functions ---- *)

  (* The elementary functions, each with the error in the module's table: the
     square root, e^x, the natural logarithm, the logarithm to the base, and
     base^exp. *)
  PROCEDURE sqrt*(x: REAL): REAL;
  BEGIN
    IF x < 0 THEN
      ErrorHandler(IllegalRoot);
      x := -x
    END;
    RETURN Of(Sqrt, x)
  END sqrt;

  PROCEDURE exp*(x: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF ~Call(Exp, x, x, result) THEN RETURN Overflowed(FALSE) END;
    IF result = 0 THEN ErrorHandler(Underflow) END;
    RETURN result
  END exp;

  PROCEDURE ln*(x: REAL): REAL;
  BEGIN
    IF x <= 0 THEN
      ErrorHandler(IllegalLog);
      RETURN -large
    END;
    RETURN Of(Log, x)
  END ln;

  PROCEDURE log*(x, base: REAL): REAL;
  BEGIN
    IF (base <= 0) OR (base = 1) THEN
      ErrorHandler(IllegalLogBase);
      RETURN -large
    ELSIF x <= 0 THEN
      ErrorHandler(IllegalLog);
      RETURN -large
    END;
    RETURN Of(Log, x) / Of(Log, base)
  END log;

  PROCEDURE power*(base, exp: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF base <= 0 THEN
      IF base # 0 THEN
        ErrorHandler(IllegalPower);
        base := -base
      ELSIF exp > 0 THEN
        RETURN 0
      ELSE
        ErrorHandler(IllegalPower);
        RETURN large
      END
    END;
    IF ~Call(Power, base, exp, result) THEN RETURN Overflowed(FALSE) END;
    IF result = 0 THEN ErrorHandler(Underflow) END;
    RETURN result
  END power;

  (* x to the whole power base (despite its name, voc's, base is the
     exponent); x^0 is 1, 0^0 included. *)
  PROCEDURE ipower*(x: REAL; base: INTEGER): REAL;
    VAR n: SYSTEM.INT32; result: REAL;
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
  PROCEDURE sin*(x: REAL): REAL;
  BEGIN
    RETURN Of(Sin, x)
  END sin;

  PROCEDURE cos*(x: REAL): REAL;
  BEGIN
    RETURN Of(Cos, x)
  END cos;

  PROCEDURE tan*(x: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF ~Call(Tan, x, x, result) THEN RETURN Overflowed(FALSE) END;
    RETURN result
  END tan;

  (* The sine and cosine of x at once. *)
  PROCEDURE sincos*(x: REAL; VAR Sin, Cos: REAL);
  BEGIN
    Sin := sin(x);
    Cos := cos(x)
  END sincos;

  (* The inverse trigonometric functions, in radians: arcsin in -pi/2..pi/2,
     arccos in 0..pi, arctan in -pi/2..pi/2. *)
  PROCEDURE arcsin*(x: REAL): REAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      ErrorHandler(IllegalInvTrig);
      RETURN large
    END;
    RETURN Of(Asin, x)
  END arcsin;

  PROCEDURE arccos*(x: REAL): REAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      ErrorHandler(IllegalInvTrig);
      RETURN large
    END;
    RETURN Of(Acos, x)
  END arccos;

  PROCEDURE arctan*(x: REAL): REAL;
  BEGIN
    RETURN Of(Atan, x)
  END arctan;

  (* The angle of the point (xd, xn) from the positive x-axis, in -pi..pi: the
     arctangent of xn / xd in the right quadrant. *)
  PROCEDURE arctan2*(xn, xd: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF (xn = 0) & (xd = 0) THEN
      ErrorHandler(IllegalTrig);
      RETURN 0
    END;
    IF Call(Atan2, xn, xd, result) THEN END;
    RETURN result
  END arctan2;

  (* The hyperbolic functions and their inverses. *)
  PROCEDURE sinh*(x: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF ~Call(Sinh, x, x, result) THEN RETURN Overflowed(x < 0) END;
    RETURN result
  END sinh;

  PROCEDURE cosh*(x: REAL): REAL;
    VAR result: REAL;
  BEGIN
    IF ~Call(Cosh, x, x, result) THEN RETURN Overflowed(FALSE) END;
    RETURN result
  END cosh;

  PROCEDURE tanh*(x: REAL): REAL;
  BEGIN
    RETURN Of(Tanh, x)
  END tanh;

  (* ln(1 + u), u >= 0, without the loss of u's digits that adding it to 1
     would cost: ln(w) * u / (w - 1), w being 1 + u as rounded, which
     corrects for the rounding *)
  PROCEDURE LnOnePlus(u: REAL): REAL;
    VAR w: REAL;
  BEGIN
    w := 1 + u;
    IF w = 1 THEN RETURN u END;
    RETURN Of(Log, w) * (u / (w - 1))
  END LnOnePlus;

  (* Beyond this, sqrt(x^2 +- 1) is |x| to every bit *)
  PROCEDURE Huge(x: REAL): BOOLEAN;
  BEGIN
    RETURN x > 4096.0 (* 2^(places DIV 2) *)
  END Huge;

  PROCEDURE arcsinh*(x: REAL): REAL;
    VAR a, result: REAL;
  BEGIN
    a := ABS(x);
    IF Huge(a) THEN
      result := Of(Log, a) + ln2
    ELSIF a >= 0.5 THEN
      result := Of(Log, 2 * a + 1 / (Of(Sqrt, a * a + 1) + a))
    ELSE
      result := LnOnePlus(a + a * a / (1 + Of(Sqrt, 1 + a * a)))
    END;
    IF x < 0 THEN RETURN -result ELSE RETURN result END
  END arcsinh;

  PROCEDURE arccosh*(x: REAL): REAL;
    VAR t: REAL;
  BEGIN
    IF x < 1 THEN
      ErrorHandler(IllegalHypInvTrig);
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

  PROCEDURE arctanh*(x: REAL): REAL;
  BEGIN
    IF (x >= 1) OR (x <= -1) THEN
      ErrorHandler(IllegalHypInvTrig);
      IF x < 0 THEN RETURN -TanhMax ELSE RETURN TanhMax END
    END;
    RETURN Of(Atanh, x)
  END arctanh;

  (* x rounded to the nearest whole number, halves away from zero; a number
     that rounds beyond LONGINT gives its largest or smallest value. *)
  PROCEDURE round*(x: REAL): LONGINT;
    VAR d: LONGREAL; n: LONGINT;
  BEGIN
    d := LONG(x);
    IF d >= MAX(LONGINT) - 0.5D0 THEN RETURN MAX(LONGINT)
    ELSIF d <= -MAX(LONGINT) - 0.5D0 THEN RETURN MIN(LONGINT)
    ELSIF d >= 0 THEN
      n := ENTIER(d);
      IF d - n >= 0.5D0 THEN INC(n) END;
      RETURN n
    ELSE
      n := ENTIER(-d);
      IF -d - n >= 0.5D0 THEN INC(n) END;
      RETURN -n
    END
  END round;

  (* -1, 0 or 1 as x is less than, approximately equal to, or greater than
     y, "approximately" meaning within epsilon times the larger power of 2
     at or below the larger of |x| and |y| (the GNU Scientific Library's
     gsl_fcmp, as voc's). *)
  PROCEDURE fcmp*(x, y, epsilon: REAL): INTEGER;
    VAR larger: REAL; delta, difference: LONGREAL;
  BEGIN
    IF ABS(x) > ABS(y) THEN larger := x ELSE larger := y END;
    delta := 2.0D0 * epsilon * scale(1.0, exponent(larger));
    difference := LONG(x) - LONG(y);
    IF difference > delta THEN RETURN 1
    ELSIF difference < -delta THEN RETURN -1
    ELSE RETURN 0
    END
  END fcmp;

BEGIN
  ErrorHandler := DefaultErrorHandler;
  err := NoError;
  TanhMax := Of(Atanh, 1.0 - scale(1.0, -places))
END Math.
