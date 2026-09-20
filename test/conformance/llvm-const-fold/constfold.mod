MODULE constfold;
  (* PLAN.md Phase 9 step 10: a constant integer expression is folded, to
     a constant of the minimal type its value fits. Before, 2 * 100 + 2 * 10
     was generated as three 8-bit instructions and wrapped to -36; now it is
     the INTEGER 220, as under voc. Each check prints "FAIL nn " on failure;
     the run ends with "OK". The names below ending in Const are constants
     whose type is part of what is tested. The part between the "poc only"
     markers (a MAX(LONGREAL) that voc, deliberately, does not give, and a
     MAX(REAL) that voc's generated C rounds to 8 digits) is dropped when
     the program is cross-checked under voc, which passes every other
     check under its default -O2 sizes; under -OC several of the values
     below are different, since SHORTINT and INTEGER are wider. *)

  CONST
    total = 2 * 100 + 2 * 10;         (* 220: INTEGER *)
    beyondShort = MAX(SHORTINT) + 1;  (* 128: INTEGER *)
    lowShort = -MAX(SHORTINT) - 1;    (* -128: SHORTINT *)
    million = 1000 * 1000;            (* LONGINT *)
    wide = 100000 * 100000;           (* 10^10: HUGEINT *)
    shifted = ASH(1, 20);
    hugeShift = ASH(1, 40);
    ten = 1000 DIV 100;
    six = 1000 MOD 7;
    bigReal = MAX(REAL);
    lowReal = MIN(REAL);
    bigLong = MAX(LONGREAL);
    lowLong = MIN(LONGREAL);
    length = 10 * 20;

  TYPE
    Grid = ARRAY 10 * 20 OF INTEGER;

  VAR
    s: SHORTINT; i, k: INTEGER; l: LONGINT; h: HUGEINT;
    r: REAL; d: LONGREAL; b: BOOLEAN; x: SET; grid: Grid;

  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Check(number: INTEGER; ok: BOOLEAN);
    VAR msg: ARRAY 9 OF CHAR;
  BEGIN
    IF ~ok THEN
      msg[0] := "F"; msg[1] := "A"; msg[2] := "I"; msg[3] := "L"; msg[4] := " ";
      msg[5] := CHR(ORD("0") + number DIV 10); msg[6] := CHR(ORD("0") + number MOD 10);
      msg[7] := " "; msg[8] := 0X;
      SysWrite(1, msg, 8)
    END
  END Check;

  PROCEDURE TakeShort(v: SHORTINT): INTEGER;
  BEGIN RETURN v END TakeShort;

  PROCEDURE TakeLong(v: LONGINT): LONGINT;
  BEGIN RETURN v END TakeLong;

  PROCEDURE TakeHuge(v: HUGEINT): HUGEINT;
  BEGIN RETURN v END TakeHuge;

  PROCEDURE Sum(): INTEGER;
  BEGIN RETURN 2 * 100 + 2 * 10 END Sum;

  PROCEDURE Local(): INTEGER;
    CONST two = 2 * 100;
    VAR v: INTEGER;
  BEGIN
    v := two + 2 * 10;
    RETURN v
  END Local;

BEGIN
  (* 1-3: the regression itself, in a statement, through a constant, in a
     function result *)
  i := 2 * 100 + 2 * 10;
  Check(1, i = 220);
  i := total;
  Check(2, i = 220);
  Check(3, Sum() = 220);

  (* 4-8: a negative numeral is the type of its negative value *)
  s := -128;
  Check(4, s = -128);
  i := -32768;
  Check(5, i = -32768);
  l := -2147483648;
  Check(6, l = -2147483648);
  s := lowShort;
  Check(7, s = -128);
  i := -(2 * 100);
  Check(8, i = -200);

  (* 9-16: each operation re-derives the type, so a value one past a
     type's range is the next type up and does not wrap *)
  s := 100 + 27;
  Check(9, s = 127);
  i := 127 + 1;
  Check(10, i = 128);
  i := beyondShort;
  Check(11, i = 128);
  l := 32767 + 1;
  Check(12, l = 32768);
  l := million;
  Check(13, l = 1000000);
  h := 2147483647 + 1;
  Check(14, h = 2147483648);
  h := 100000 * 100000;
  Check(15, h = 10000000000);
  h := wide;
  Check(16, h = 10000000000);

  (* 17-22: DIV and MOD fold with the floored semantics *)
  i := (-7) DIV 2;
  Check(17, i = -4);
  i := (-7) MOD 2;
  Check(18, i = 1);
  i := 7 DIV 2;
  Check(19, i = 3);
  s := ten;
  Check(20, s = 10);
  s := six;
  Check(21, s = 6);
  i := (-8) DIV 2 + (-1) MOD 5;
  Check(22, i = 0);

  (* 23-27: a constant inside an expression that is not constant keeps
     the run-time type of the rest; the run-time SHORTINT still wraps *)
  i := 1000; i := i + 100 * 200;
  Check(23, i = 21000);
  s := 100; i := s * 200;
  Check(24, i = 20000);
  s := 100; s := s * 2;
  Check(25, s = -56);
  l := 100000; l := l + 100 * 100 * 100;
  Check(26, l = 1100000);
  i := 3; i := i * (2 * 100 + 2 * 10);
  Check(27, i = 660);

  (* 28-33: ASH of constants *)
  l := shifted;
  Check(28, l = 1048576);
  h := hugeShift;
  Check(29, h = 1099511627776);
  l := ASH(-1000, -3);
  Check(30, l = -125);
  h := ASH(1, 62);
  Check(31, h = 4611686018427387904);
  l := ASH(1, 2 + 3);
  Check(32, l = 32);
  h := ASH(-1, 62);
  Check(33, h = -4611686018427387904);

  (* 34-36: HUGEINT comparisons of constants are exact, not through a
     LONGREAL that cannot tell 2^63-1 from 2^63-2 *)
  b := MAX(HUGEINT) = MAX(HUGEINT) - 1;
  Check(34, ~b);
  b := MAX(HUGEINT) - 1 < MAX(HUGEINT);
  Check(35, b);
  h := MAX(HUGEINT) - 1 + 1;
  Check(36, h = MAX(HUGEINT));

  (* 37-42: constants as arguments, and in the places a constant is needed *)
  Check(37, TakeShort(-128) = -128);
  Check(38, TakeLong(100 * 1000 * 100) = 10000000);
  Check(39, TakeHuge(100000 * 100000) = 10000000000);
  Check(40, LEN(grid) = 200);
  Check(41, length = 200);
  Check(42, Local() = 220);

  (* 43-45: a CASE label and a FOR step that are constant expressions *)
  i := 220;
  CASE i OF
    2 * 100 + 2 * 10: k := 1
  | 0: k := 2
  END;
  Check(43, k = 1);
  k := 0;
  FOR i := 0 TO 100 BY 2 * 5 DO INC(k) END;
  Check(44, k = 11);
  x := {100 - 99, 2 * 2};
  Check(45, (1 IN x) & (4 IN x) & ~(2 IN x));

  (* 46-51: MAX and MIN of REAL and LONGREAL as constants *)
  r := bigReal;
  Check(46, (r / 1.0E30 > 3.0E8) & (r / 1.0E30 < 3.5E8));
  r := lowReal;
  Check(47, (r / 1.0E30 < -3.0E8) & (r / 1.0E30 > -3.5E8));
  d := bigLong;
  Check(48, (d / 1.0D300 > 1.79D8) & (d / 1.0D300 < 1.8D8));
  d := lowLong;
  Check(49, (d / 1.0D300 < -1.79D8) & (d / 1.0D300 > -1.8D8));
  d := MIN(LONGREAL);
  Check(50, d = lowLong);
  (* poc only *)
  r := MAX(REAL); d := r;
  Check(51, d = MAX(REAL));
  d := bigLong;
  Check(52, d / 1.0D300 > 1.797693D8);
  (* poc only *)

  SysWrite(1, "OK", 2)
END constfold.
