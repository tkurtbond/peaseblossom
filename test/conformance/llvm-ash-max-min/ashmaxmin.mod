MODULE ashmaxmin;
  (* PLAN.md Phase 9 step 8: ASH, MAX and MIN, the last of Oberon2.pdf
     10.3's predeclared procedures to be lowered. ASH(x, n) shifts x left
     n places, or right (flooring) for a negative n, in LONGINT or x's own
     type if that is wider; MAX(T)/MIN(T) are constants. Each check prints
     "FAIL nn " on failure; the run ends with "OK". A shift that overflows
     LONGINT is stored in a LONGINT before it is compared, since voc
     compares the 64-bit value it computed it in. The part between the
     "poc only" markers (ASH by 64 places or more, which voc leaves to the
     C compiler) is dropped when the program is cross-checked under voc. *)
  TYPE
    Small = SHORTINT;
  VAR
    s: SHORTINT; i: INTEGER; l, m: LONGINT; h, g: HUGEINT;
    r, r2: REAL; d: LONGREAL; c: CHAR; b: BOOLEAN; set: SET;
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

  PROCEDURE Shift(x, n: LONGINT): LONGINT;
  BEGIN RETURN ASH(x, n) END Shift;

BEGIN
  (* 1-6: left shifts, and no shift *)
  l := 1;
  Check(1, ASH(l, 4) = 16);
  l := 5;
  Check(2, ASH(l, 1) = 10);
  Check(3, ASH(l, 0) = 5);
  l := -3; i := 4;
  Check(4, ASH(l, i) = -48);
  Check(5, Shift(7, 3) = 56);
  Check(6, Shift(0, 20) = 0);

  (* 7-12: right shifts floor, as an arithmetic shift does *)
  l := 16; i := -2;
  Check(7, ASH(l, i) = 4);
  l := -16;
  Check(8, ASH(l, i) = -4);
  l := -1;
  Check(9, ASH(l, -5) = -1);
  l := -7;
  Check(10, ASH(l, -1) = -4);
  l := 7;
  Check(11, ASH(l, -1) = 3);
  Check(12, Shift(1000, -3) = 125);

  (* 13-18: the width of the type bounds what a left shift keeps, and a
     count past it leaves nothing (0), or for a right shift just the sign *)
  l := 1; m := 31;
  m := ASH(l, m);
  Check(13, m = MIN(LONGINT));
  m := 32;
  m := ASH(l, m);
  Check(14, m = 0);
  l := 3; m := 40;
  m := ASH(l, m);
  Check(15, m = 0);
  l := -5; m := -40;
  Check(16, ASH(l, m) = -1);
  l := 5;
  Check(17, ASH(l, m) = 0);
  m := 63; l := 1;
  m := ASH(l, m);
  Check(18, m = 0);
  m := -63; l := -9;
  Check(19, ASH(l, m) = -1);

  (* 20-24: SHORTINT and INTEGER operands are widened before the shift *)
  s := 100;
  Check(20, ASH(s, 8) = 25600);
  s := -100;
  Check(21, ASH(s, 8) = -25600);
  i := 20000;
  Check(22, ASH(i, 4) = 320000);
  l := ASH(i, -4);
  Check(23, l = 1250);
  s := 1; i := 15;
  l := ASH(s, i);
  Check(24, l = 32768);

  (* 25-30: HUGEINT keeps its 64 bits *)
  h := 1;
  g := ASH(h, 40);
  Check(25, (g DIV 1024 DIV 1024 DIV 1024 DIV 1024 = 1) & (g MOD 1024 = 0));
  g := ASH(g, -40);
  Check(26, g = 1);
  h := 1; g := 62;
  h := ASH(h, g);
  Check(27, h > 0);
  h := ASH(h, 1);
  Check(28, h = MIN(HUGEINT));
  g := ASH(h, -63);
  Check(29, g = -1);
  h := 3; g := ASH(h, 33);
  Check(30, g DIV 8589934592 = 3);
  (* the count itself may be HUGEINT *)
  h := 3; g := -1;
  Check(31, ASH(h, g) = 1);

  (* poc only begin *)
  l := 1; m := 64;
  Check(32, ASH(l, m) = 0);
  m := 1000000;
  Check(33, ASH(l, m) = 0);
  h := 5; g := 4000000000; g := g * 4000000000;
  Check(34, ASH(l, g) = 0);
  l := -3; m := -64;
  Check(35, ASH(l, m) = -1);
  l := 3;
  Check(36, ASH(l, m) = 0);
  h := MIN(HUGEINT);
  Check(37, ASH(l, h) = 0);
  h := MAX(HUGEINT);
  Check(38, ASH(l, h) = 0);
  (* poc only end *)

  (* 40-52: the bounds of the integer types (voc's, and poc's default, -O2) *)
  Check(40, MAX(SHORTINT) = 127);
  Check(41, MIN(SHORTINT) = -128);
  Check(42, MAX(INTEGER) = 32767);
  Check(43, MIN(INTEGER) = -32768);
  Check(44, MAX(LONGINT) = 2147483647);
  Check(45, MIN(LONGINT) = -2147483647 - 1);
  h := MAX(HUGEINT); g := MIN(HUGEINT);
  Check(46, (h > 0) & (g < 0) & (h + g = -1));
  Check(47, MAX(Small) = 127);
  s := MAX(SHORTINT); i := s; i := i + 1;
  Check(48, i = 128);
  i := MIN(INTEGER); l := i; l := l - 1;
  Check(49, l = -32769);
  i := MAX(INTEGER) - 1;
  Check(50, i = 32766);

  (* 51-57: CHAR, BOOLEAN, SET *)
  c := MAX(CHAR);
  Check(51, ORD(c) = 255);
  c := MIN(CHAR);
  Check(52, ORD(c) = 0);
  b := MAX(BOOLEAN);
  Check(53, b);
  b := MIN(BOOLEAN);
  Check(54, ~b);
  i := MAX(SET);
  Check(55, i = 31);
  i := MIN(SET);
  Check(56, i = 0);
  set := {MIN(SET), MAX(SET)};
  Check(57, (0 IN set) & (31 IN set) & ~(1 IN set));

  (* 58-63: REAL and LONGREAL, the largest finite values *)
  r := MAX(REAL);
  d := r;
  Check(58, (d > 1.0D38) & (d / 2.0D0 > 1.0D38) & (r / 2.0 < r));
  r2 := MIN(REAL);
  Check(59, r2 = -r);
  d := MAX(LONGREAL);
  Check(60, (d > 1.0D300) & (d / 2.0D0 > 1.0D300));
  Check(61, MIN(LONGREAL) = -d);
  d := MAX(REAL);
  Check(62, (d > 1.0D38) & (d < 1.0D39));
  d := MIN(LONGREAL);
  Check(63, (d < 0.0D0) & (d / 2.0D0 > d));

  SysWrite(1, "OK", 2)
END ashmaxmin.
