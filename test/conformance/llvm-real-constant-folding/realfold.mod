MODULE realfold;
  (* A REAL constant expression folds to what the same expression gives at
     run time: each operand is a REAL's single-precision value (a numeral
     rounded once, straight from its text), an integer in a REAL operation
     is converted to REAL, and each REAL result is rounded to single.
     ConstantEvaluator used to fold REAL expressions in double precision,
     so SHORT(0.1D0) = 0.1 and 0.1 + 0.2 = 0.3 folded to FALSE where they
     are TRUE at run time; poc's VAX backend, which folds an IF's
     condition, printed "FAIL 27" for llvm-reals (Phase 16 step 5).
     Each check compares a folded BOOLEAN constant with the same
     comparison made at run time on variables, and prints "FAIL nn " if
     they differ; the run ends with "OK". Each result is stored in a
     variable before it is compared: 32-bit x86 computes REALs in the
     x87's extended precision and rounds them only when it stores them. *)
  IMPORT Out;
  CONST
    shortEqual = SHORT(0.1D0) = 0.1;
    shortLess = 0.1 < SHORT(0.1D0);
    sumEqual = 0.1 + 0.2 = 0.3;
    sumGreater = 0.1 + 0.2 > 0.3;
    quotientEqual = 1.0 / 10.0 = 0.1;
    productEqual = 0.1 * 3.0 = 0.3;
    differenceEqual = 0.3 - 0.1 = 0.2;
    thirdsEqual = 1.0 / 3.0 * 3.0 = 1.0;
    integerSumEqual = 16777217 + 0.0 = 16777216.0;
    mixedEqual = 0.1 + 0.1D0 = 0.2D0;
    longEqual = LONG(0.1) = 0.1D0;
    entierOne = ENTIER(0.99999999) = 1;
    negatedEqual = -0.1 = -SHORT(0.1D0);
    absoluteEqual = ABS(-0.1) = SHORT(0.1D0);
    quotientOfIntegers = 1 / 3 = 1.0 / 3.0;
  VAR
    x, y, z, result: REAL;
    d, e, longResult: LONGREAL;
    i: LONGINT;

  PROCEDURE Check(number: INTEGER; folded, computed: BOOLEAN);
  BEGIN
    IF folded # computed THEN
      Out.String("FAIL "); Out.Char(CHR(ORD("0") + number DIV 10));
      Out.Char(CHR(ORD("0") + number MOD 10)); Out.Char(" ")
    END
  END Check;

BEGIN
  d := 0.1D0; x := SHORT(d); y := 0.1;
  Check(1, shortEqual, x = y);
  Check(2, shortLess, y < x);
  x := 0.1; y := 0.2; z := 0.3;
  result := x + y;
  Check(3, sumEqual, result = z);
  Check(4, sumGreater, result > z);
  x := 1.0; y := 10.0; z := 0.1;
  result := x / y;
  Check(5, quotientEqual, result = z);
  x := 0.1; y := 3.0; z := 0.3;
  result := x * y;
  Check(6, productEqual, result = z);
  x := 0.3; y := 0.1; z := 0.2;
  result := x - y;
  Check(7, differenceEqual, result = z);
  x := 1.0; y := 3.0; z := 1.0;
  result := x / y; result := result * y;
  Check(8, thirdsEqual, result = z);
  i := 16777217; x := 0.0; y := 16777216.0;
  result := i + x;
  Check(9, integerSumEqual, result = y);
  x := 0.1; d := 0.1D0; e := 0.2D0;
  longResult := x + d;
  Check(10, mixedEqual, longResult = e);
  longResult := LONG(x);
  Check(11, longEqual, longResult = d);
  x := 0.99999999;
  Check(12, entierOne, ENTIER(x) = 1);
  x := 0.1; d := 0.1D0; y := SHORT(d);
  result := -x; z := -y;
  Check(13, negatedEqual, result = z);
  x := -0.1;
  result := ABS(x);
  Check(14, absoluteEqual, result = y);
  i := 1; x := 1.0; y := 3.0;
  result := i / 3; z := x / y;
  Check(15, quotientOfIntegers, result = z);
  Out.String("OK"); Out.Ln
END realfold.
