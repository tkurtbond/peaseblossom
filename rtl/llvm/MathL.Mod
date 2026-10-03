MODULE MathL;

  (* PLAN.md Phase 10 step 6: the Oakwood LONGREAL mathematics, the same
     functions as Math (see there for the error codes, what comes back with
     each, and how this differs from voc's) on LONGREAL, with the interface
     of voc's MathL: everything Math has except the error handler, whose
     ErrorHandler, err, ClearError and codes live in Math; a MathL function
     reports through Math.ErrorHandler.

     Each function is one call of the C library's double function (sqrt,
     sin, exp, ... in libm) plus the error checks, so the result is what
     libm gives: to within an ulp or better, and correctly rounded for
     sqrt. Not derived from voc's MathL, which is the OOC library's
     polynomial approximations under the LGPL.

     Differences from Math beyond the width:
     - `large` is MAX(LONGREAL) and `small` the smallest normal LONGREAL,
       2^-1022 (voc's `small` is 0: its expression underflows).
     - voc's MathL raises no Underflow; here exp and power report it when
       the result is 0, as Math does. *)

  IMPORT SYSTEM, Math;

  CONST
    (* pi and e; the number of bits in the fraction (with its leading 1); the
       largest number and the smallest normal one; the largest and smallest
       exponent of a normal number *)
    pi* = 3.14159265358979323846D0;
    e* = 2.71828182845904523536D0;
    places* = 53;
    large* = MAX(LONGREAL);
    small* = 2.2250738585072014D-308;
    expoMax* = 1023;
    expoMin* = -1022;

  VAR
    TanhMax: LONGREAL; (* what arctanh gives for a number at or beyond +-1 *)

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
  PROCEDURE ["C", "nextafter"] CNextAfter(x, toward: LONGREAL): LONGREAL;

  (* Always FALSE: an error goes to the error handler, never to an exception
     (voc's interface keeps it from the ISO library). *)
  PROCEDURE IsRMathException*(): BOOLEAN;
  BEGIN
    RETURN FALSE
  END IsRMathException;

  (* d, or +-large and an Overflow if it is beyond the range (an infinity). *)
  PROCEDURE Limit(d: LONGREAL): LONGREAL;
  BEGIN
    IF d > large THEN
      Math.ErrorHandler(Math.Overflow);
      RETURN large
    ELSIF d < -large THEN
      Math.ErrorHandler(Math.Overflow);
      RETURN -large
    END;
    RETURN d
  END Limit;

  PROCEDURE Finite(x: LONGREAL): BOOLEAN;
  BEGIN
    RETURN (x - x) = 0
  END Finite;

  (* ---- real number properties ---- *)

  (* The exponent of x, the power of 2 with x = fraction(x) * 2^exponent(x):
     0 for 0, expoMax + 1 for an infinity or a not-a-number. *)
  PROCEDURE exponent*(x: LONGREAL): INTEGER;
  BEGIN
    IF x = 0 THEN RETURN 0 END;
    IF ~Finite(x) THEN RETURN expoMax + 1 END;
    RETURN SHORT(ENTIER(CLogb(x)))
  END exponent;

  (* x without its exponent, 1 <= |fraction(x)| < 2; 0, an infinity or a
     not-a-number comes back as it is. *)
  PROCEDURE fraction*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x = 0) OR ~Finite(x) THEN RETURN x END;
    RETURN CLdexp(x, -exponent(x))
  END fraction;

  (* -1 if x is negative, else 1 (0 included). *)
  PROCEDURE sign*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x < 0 THEN RETURN -1 ELSE RETURN 1 END
  END sign;

  (* x * 2^n, exactly where the result is representable. *)
  PROCEDURE scale*(x: LONGREAL; n: INTEGER): LONGREAL;
  BEGIN
    IF (x = 0) OR ~Finite(x) THEN RETURN x END;
    RETURN Limit(CLdexp(x, n))
  END scale;

  (* The distance from |x| to the next larger number of x's exponent: one
     unit in the last place. *)
  PROCEDURE ulp*(x: LONGREAL): LONGREAL;
    VAR expo: INTEGER;
  BEGIN
    expo := exponent(x);
    IF (x = 0) OR (expo < expoMin) THEN expo := expoMin END;
    RETURN CLdexp(1.0D0, expo - places + 1)
  END ulp;

  (* The next number above x, pred the next below it. *)
  PROCEDURE succ*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x >= large THEN
      Math.ErrorHandler(Math.Overflow);
      RETURN large
    END;
    RETURN CNextAfter(x, large)
  END succ;

  PROCEDURE pred*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x <= -large THEN
      Math.ErrorHandler(Math.Overflow);
      RETURN -large
    END;
    RETURN CNextAfter(x, -large)
  END pred;

  (* ---- elementary functions ---- *)

  (* The elementary functions, each with the error in the module's table: the
     square root, e^x, the natural logarithm, the logarithm to the base, and
     base^exp. *)
  PROCEDURE sqrt*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x < 0 THEN
      Math.ErrorHandler(Math.IllegalRoot);
      x := -x
    END;
    RETURN CSqrt(x)
  END sqrt;

  PROCEDURE exp*(x: LONGREAL): LONGREAL;
    VAR result: LONGREAL;
  BEGIN
    result := Limit(CExp(x));
    IF (result = 0) & (x = x) THEN Math.ErrorHandler(Math.Underflow) END;
    RETURN result
  END exp;

  PROCEDURE ln*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x <= 0 THEN
      Math.ErrorHandler(Math.IllegalLog);
      RETURN -large
    END;
    RETURN CLog(x)
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
    RETURN Limit(CLog(x) / CLog(base))
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
    result := Limit(CPow(base, exp));
    IF (result = 0) & (base = base) & (exp = exp) THEN Math.ErrorHandler(Math.Underflow) END;
    RETURN result
  END power;

  (* x to the whole power base (despite its name, voc's, base is the exponent). *)
  PROCEDURE ipower*(x: LONGREAL; base: INTEGER): LONGREAL;
  BEGIN
    RETURN Limit(CPow(x, base))
  END ipower;

  (* The trigonometric functions, in radians. *)
  PROCEDURE sin*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN CSin(x)
  END sin;

  PROCEDURE cos*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN CCos(x)
  END cos;

  PROCEDURE tan*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Limit(CTan(x))
  END tan;

  (* The sine and cosine of x at once. *)
  PROCEDURE sincos*(x: LONGREAL; VAR Sin, Cos: LONGREAL);
  BEGIN
    Sin := CSin(x);
    Cos := CCos(x)
  END sincos;

  (* The inverse trigonometric functions, in radians: arcsin in -pi/2..pi/2,
     arccos in 0..pi, arctan in -pi/2..pi/2. *)
  PROCEDURE arcsin*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      Math.ErrorHandler(Math.IllegalInvTrig);
      RETURN large
    END;
    RETURN CAsin(x)
  END arcsin;

  PROCEDURE arccos*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x > 1) OR (x < -1) THEN
      Math.ErrorHandler(Math.IllegalInvTrig);
      RETURN large
    END;
    RETURN CAcos(x)
  END arccos;

  PROCEDURE arctan*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN CAtan(x)
  END arctan;

  (* The angle of the point (xd, xn) from the positive x-axis, in -pi..pi: the
     arctangent of xn / xd in the right quadrant. *)
  PROCEDURE arctan2*(xn, xd: LONGREAL): LONGREAL;
  BEGIN
    IF (xn = 0) & (xd = 0) THEN
      Math.ErrorHandler(Math.IllegalTrig);
      RETURN 0
    END;
    RETURN CAtan2(xn, xd)
  END arctan2;

  (* The hyperbolic functions and their inverses. *)
  PROCEDURE sinh*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Limit(CSinh(x))
  END sinh;

  PROCEDURE cosh*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN Limit(CCosh(x))
  END cosh;

  PROCEDURE tanh*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN CTanh(x)
  END tanh;

  PROCEDURE arcsinh*(x: LONGREAL): LONGREAL;
  BEGIN
    RETURN CAsinh(x)
  END arcsinh;

  PROCEDURE arccosh*(x: LONGREAL): LONGREAL;
  BEGIN
    IF x < 1 THEN
      Math.ErrorHandler(Math.IllegalHypInvTrig);
      RETURN 0
    END;
    RETURN CAcosh(x)
  END arccosh;

  PROCEDURE arctanh*(x: LONGREAL): LONGREAL;
  BEGIN
    IF (x >= 1) OR (x <= -1) THEN
      Math.ErrorHandler(Math.IllegalHypInvTrig);
      IF x < 0 THEN RETURN -TanhMax ELSE RETURN TanhMax END
    END;
    RETURN CAtanh(x)
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
    delta := 2.0D0 * epsilon * CLdexp(1.0D0, exponent(larger));
    difference := x - y;
    IF difference > delta THEN RETURN 1
    ELSIF difference < -delta THEN RETURN -1
    ELSE RETURN 0
    END
  END fcmp;

BEGIN
  TanhMax := CAtanh(1.0D0 - CLdexp(1.0D0, -places))
END MathL.
