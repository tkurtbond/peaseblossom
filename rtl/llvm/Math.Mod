MODULE Math;

  (* PLAN.md Phase 10 step 6: the Oakwood REAL mathematics, with the
     interface of voc's Math (which adapts the ISO RealMath of the OOC
     library, adding log, ipower, sincos, arctan2, fcmp and the error
     handler), so a program using it runs unchanged under either compiler.

     Written afresh over the C library's double-precision functions (sqrt,
     sin, exp, ... : the same names on Linux, NetBSD, OpenBSD and FreeBSD,
     in libm, which the build now links), not derived from voc's, which is
     the OOC library's polynomial approximations under the LGPL. A REAL
     function widens its argument, calls the double function and rounds the
     result once, so it is correct to within a rounding of the double
     result (voc's own approximations are good to an ulp or two of a REAL).
     The real-number properties (exponent, fraction, scale, ulp, succ, pred)
     are exact.

     Errors: a call that cannot give a real answer reports an error code
     through ErrorHandler and returns a fixed value, as in voc. The default
     handler stores the code in err (ClearError sets it back to NoError); a
     program may install its own, taking the code as its argument, and a
     handler that returns lets the function go on to its return value.
     MathL reports through this same handler. What is an error, and what
     comes back:

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

     Where this differs from voc's (the numbers are those of vishap-bugs,
     ~/Repos/Oberon/vishap-bugs):

     - sin, cos and tan give an answer for every argument (48), and from
       libm, so with no error from constants that lose digits (03).
     - exp reports Underflow only when the result is really 0 (55); arcsinh
       and arccosh have no clipping error (56).
     - sincos gives the true cosine (38); succ and pred give the
       neighbouring numbers (39); sign(0) is 1, as in voc.
       fraction/exponent/scale/ulp are right for denormals too (42, 54):
       the exponent of a denormal is below expoMin, since it is the
       exponent the number would have with a longer exponent field.
     - Lengths and codes are INTEGER, and round is LONGINT - the Oakwood
       interface's own types, which follow the size model, so they are not
       SYSTEM.INT16/INT32 (fixed-width; used only for the C `int` of ldexp).
       round rounds halves away from zero, as voc's (D10), and gives
       MAX(LONGINT)/MIN(LONGINT) for a number out of range (voc's wraps:
       D22). *)

  IMPORT SYSTEM;

  CONST
    (* pi and e; the number of bits in the fraction (with its leading 1); the
       largest number and the smallest normal one; the largest and smallest
       exponent of a normal number *)
    pi* = 3.14159265358979323846;
    e* = 2.71828182845904523536;
    places* = 24;
    large* = MAX(REAL);
    small* = 1.17549435E-38;
    expoMax* = 127;
    expoMin* = -126;

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

  VAR
    (* Called with the error code of a function that cannot give a real
       answer; at first a handler that stores the code in err. *)
    ErrorHandler*: PROCEDURE (errno: INTEGER);
    err-: INTEGER;
    TanhMax: REAL; (* what arctanh gives for a number at or beyond +-1 *)

  (* libm. The C type int is written LONGINT, as in Platform.Mod. *)
  PROCEDURE ["C", "sqrt"] CSqrt(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "sin"] CSin(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "cos"] CCos(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "tan"] CTan(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "asin"] CAsin(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "acos"] CAcos(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "atan"] CAtan(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "atan2"] CAtan2(y, x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "exp"] CExp(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "log"] CLog(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "pow"] CPow(x, y: LONGREAL): LONGREAL;
  PROCEDURE ["C", "sinh"] CSinh(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "cosh"] CCosh(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "tanh"] CTanh(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "asinh"] CAsinh(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "acosh"] CAcosh(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "atanh"] CAtanh(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "ldexp"] CLdexp(x: LONGREAL; n: SYSTEM.INT32): LONGREAL;
  PROCEDURE ["C", "logb"] CLogb(x: LONGREAL): LONGREAL;
  PROCEDURE ["C", "nextafterf"] CNextAfterF(x, toward: REAL): REAL;

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

  (* d as a REAL, or +-large (and an Overflow) if it is too large for one. *)
  PROCEDURE Narrow(d: LONGREAL): REAL;
  BEGIN
    IF d > large THEN
      ErrorHandler(Overflow);
      RETURN large
    ELSIF d < -large THEN
      ErrorHandler(Overflow);
      RETURN -large
    END;
    RETURN SHORT(d)
  END Narrow;

  (* Whether x is neither an infinity nor a not-a-number. *)
  PROCEDURE Finite(x: REAL): BOOLEAN;
  BEGIN
    RETURN (x - x) = 0
  END Finite;

  (* ---- real number properties ---- *)

  (* The exponent of x, the power of 2 with x = fraction(x) * 2^exponent(x):
     0 for 0, expoMax + 1 for an infinity or a not-a-number. *)
  PROCEDURE exponent*(x: REAL): INTEGER;
  BEGIN
    IF x = 0 THEN RETURN 0 END;
    IF ~Finite(x) THEN RETURN expoMax + 1 END;
    RETURN SHORT(ENTIER(CLogb(LONG(x))))
  END exponent;

  (* x without its exponent, 1 <= |fraction(x)| < 2; 0, an infinity or a
     not-a-number comes back as it is. *)
  PROCEDURE fraction*(x: REAL): REAL;
  BEGIN
    IF (x = 0) OR ~Finite(x) THEN RETURN x END;
    RETURN SHORT(CLdexp(LONG(x), -exponent(x)))
  END fraction;

  (* -1 if x is negative, else 1 (0 included). *)
  PROCEDURE sign*(x: REAL): REAL;
  BEGIN
    IF x < 0 THEN RETURN -1 ELSE RETURN 1 END
  END sign;

  (* x * 2^n, exactly where the result is representable. *)
  PROCEDURE scale*(x: REAL; n: INTEGER): REAL;
  BEGIN
    IF (x = 0) OR ~Finite(x) THEN RETURN x END;
    RETURN Narrow(CLdexp(LONG(x), n))
  END scale;

  (* The distance from |x| to the next larger number of x's exponent: one
     unit in the last place. *)
  PROCEDURE ulp*(x: REAL): REAL;
    VAR expo: INTEGER;
  BEGIN
    expo := exponent(x);
    (* zero and the denormals are as far apart as the smallest numbers *)
    IF (x = 0) OR (expo < expoMin) THEN expo := expoMin END;
    RETURN SHORT(CLdexp(1.0D0, expo - places + 1))
  END ulp;

  (* The next number above x, pred the next below it. *)
  PROCEDURE succ*(x: REAL): REAL;
  BEGIN
    IF x >= large THEN
      ErrorHandler(Overflow);
      RETURN large
    END;
    RETURN CNextAfterF(x, large)
  END succ;

  PROCEDURE pred*(x: REAL): REAL;
  BEGIN
    IF x <= -large THEN
      ErrorHandler(Overflow);
      RETURN -large
    END;
    RETURN CNextAfterF(x, -large)
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
    RETURN SHORT(CSqrt(LONG(x)))
  END sqrt;

  PROCEDURE exp*(x: REAL): REAL;
    VAR result: REAL;
  BEGIN
    result := Narrow(CExp(LONG(x)));
    IF (result = 0) & (x = x) THEN ErrorHandler(Underflow) END;
    RETURN result
  END exp;

  PROCEDURE ln*(x: REAL): REAL;
  BEGIN
    IF x <= 0 THEN
      ErrorHandler(IllegalLog);
      RETURN -large
    END;
    RETURN SHORT(CLog(LONG(x)))
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
    RETURN Narrow(CLog(LONG(x)) / CLog(LONG(base)))
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
    result := Narrow(CPow(LONG(base), LONG(exp)));
    IF (result = 0) & (base = base) & (exp = exp) THEN ErrorHandler(Underflow) END;
    RETURN result
  END power;

  (* x to the whole power base (despite its name, voc's, base is the exponent). *)
  PROCEDURE ipower*(x: REAL; base: INTEGER): REAL;
    VAR d: LONGREAL;
  BEGIN
    d := CPow(LONG(x), LONG(base));
    IF d > large THEN
      ErrorHandler(Overflow);
      RETURN large
    ELSIF d < -large THEN
      ErrorHandler(Overflow);
      RETURN -large
    END;
    RETURN SHORT(d)
  END ipower;

  (* The trigonometric functions, in radians. *)
  PROCEDURE sin*(x: REAL): REAL;
  BEGIN
    RETURN SHORT(CSin(LONG(x)))
  END sin;

  PROCEDURE cos*(x: REAL): REAL;
  BEGIN
    RETURN SHORT(CCos(LONG(x)))
  END cos;

  PROCEDURE tan*(x: REAL): REAL;
  BEGIN
    RETURN Narrow(CTan(LONG(x)))
  END tan;

  (* The sine and cosine of x at once. *)
  PROCEDURE sincos*(x: REAL; VAR Sin, Cos: REAL);
  BEGIN
    Sin := SHORT(CSin(LONG(x)));
    Cos := SHORT(CCos(LONG(x)))
  END sincos;

  (* The inverse trigonometric functions, in radians: arcsin in -pi/2..pi/2,
     arccos in 0..pi, arctan in -pi/2..pi/2. *)
  PROCEDURE arcsin*(x: REAL): REAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      ErrorHandler(IllegalInvTrig);
      RETURN large
    END;
    RETURN SHORT(CAsin(LONG(x)))
  END arcsin;

  PROCEDURE arccos*(x: REAL): REAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      ErrorHandler(IllegalInvTrig);
      RETURN large
    END;
    RETURN SHORT(CAcos(LONG(x)))
  END arccos;

  PROCEDURE arctan*(x: REAL): REAL;
  BEGIN
    RETURN SHORT(CAtan(LONG(x)))
  END arctan;

  (* The angle of the point (xd, xn) from the positive x-axis, in -pi..pi: the
     arctangent of xn / xd in the right quadrant. *)
  PROCEDURE arctan2*(xn, xd: REAL): REAL;
  BEGIN
    IF (xn = 0) & (xd = 0) THEN
      ErrorHandler(IllegalTrig);
      RETURN 0
    END;
    RETURN SHORT(CAtan2(LONG(xn), LONG(xd)))
  END arctan2;

  (* The hyperbolic functions and their inverses. *)
  PROCEDURE sinh*(x: REAL): REAL;
  BEGIN
    RETURN Narrow(CSinh(LONG(x)))
  END sinh;

  PROCEDURE cosh*(x: REAL): REAL;
  BEGIN
    RETURN Narrow(CCosh(LONG(x)))
  END cosh;

  PROCEDURE tanh*(x: REAL): REAL;
  BEGIN
    RETURN SHORT(CTanh(LONG(x)))
  END tanh;

  PROCEDURE arcsinh*(x: REAL): REAL;
  BEGIN
    RETURN SHORT(CAsinh(LONG(x)))
  END arcsinh;

  PROCEDURE arccosh*(x: REAL): REAL;
  BEGIN
    IF x < 1 THEN
      ErrorHandler(IllegalHypInvTrig);
      RETURN 0
    END;
    RETURN SHORT(CAcosh(LONG(x)))
  END arccosh;

  PROCEDURE arctanh*(x: REAL): REAL;
  BEGIN
    IF (x >= 1) OR (x <= -1) THEN
      ErrorHandler(IllegalHypInvTrig);
      IF x < 0 THEN RETURN -TanhMax ELSE RETURN TanhMax END
    END;
    RETURN SHORT(CAtanh(LONG(x)))
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
    delta := 2.0D0 * epsilon * CLdexp(1.0D0, exponent(larger));
    difference := LONG(x) - LONG(y);
    IF difference > delta THEN RETURN 1
    ELSIF difference < -delta THEN RETURN -1
    ELSE RETURN 0
    END
  END fcmp;

BEGIN
  ErrorHandler := DefaultErrorHandler;
  err := NoError;
  TanhMax := SHORT(CAtanh(1.0D0 - CLdexp(1.0D0, -places)))
END Math.
