MODULE VaxReals;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 9): reals, a REAL an F_floating, a LONGREAL a G_floating -
     constants, as written and as computed; arithmetic at the wider of two
     types, an integer converted, a HUGEINT by POC_QTOG; comparisons; ABS,
     LONG, SHORT and ENTIER, which floors; value and VAR parameters,
     results, a call while a LONGREAL waits in R1 and R2, a procedure
     variable, record fields, array elements, an open array, and an
     expression that spills a pair of registers. The
     debugger runs examine what it computes, and that 2^53 + 1, a HUGEINT
     converted and a sum, rounds to 2^53 + 2, away from zero, as the VAX
     rounds, where IEEE 754 rounds to even, 2^53; mode 1 takes ENTIER of
     3.0D9 (trap 8), mode 2 divides by zero, the hardware's fault. *)
  TYPE
    Point = RECORD x, y: LONGREAL; w: REAL END;
    Func = PROCEDURE (v: LONGREAL): LONGREAL;
  VAR
    constants, arith, mixed, compare, floor, conv, params, fields, spill, wide, tie, l: LONGINT;
    mode, n: INTEGER; r: REAL; x, y, z, zero: LONGREAL; h: HUGEINT; p: Point; a: ARRAY 3 OF LONGREAL;
    f: Func;

  PROCEDURE Half(v: LONGREAL): LONGREAL;
  BEGIN
    RETURN v / 2
  END Half;

  PROCEDURE Scale(g: REAL; k: INTEGER): REAL;
  BEGIN
    g := g * k; RETURN g + 0.5
  END Scale;

  PROCEDURE Twice(VAR v: LONGREAL);
  BEGIN
    v := v + v
  END Twice;

  PROCEDURE Sum(VAR q: ARRAY OF LONGREAL): LONGREAL;
    VAR i: INTEGER; t: LONGREAL;
  BEGIN
    t := 0;
    FOR i := 0 TO SHORT(LEN(q)) - 1 DO t := t + q[i] END;
    RETURN t
  END Sum;

  (* four sums at once: a pair of registers each, one more than R0-R5 *)
  PROCEDURE Spilled(): LONGREAL;
    VAR b, c, d, e, g, i, j, k: LONGREAL;
  BEGIN
    b := 1; c := 2; d := 3; e := 4; g := 5; i := 6; j := 7; k := 8;
    RETURN (b + c) * ((d + e) * ((g + i) * (j + k)))
  END Spilled;

BEGIN
  r := 1.5; z := 2.25E1; x := 0.1D0; y := 1.0D0 / 4.0D0;
  constants := ENTIER(r * 10) * 100000 + ENTIER(z) * 1000 + ENTIER(x * 30) * 100 + ENTIER(y * 8);
  x := 2.5D0; y := x * x - 1.25; y := y / 4; r := 3.0; r := r / 4 + r;
  arith := ENTIER(y * 100) * 100 + ENTIER(r * 4);
  n := 7; r := n / 2; x := n * 0.5D0 + 1; h := 3000000000; z := h / 1.0D9; l := 123456; y := l * 2;
  mixed := ENTIER(r * 2) * 1000 + ENTIER(x) * 100 + ENTIER(z) * 10 + ENTIER(y) - 246912;
  h := -5; z := h; mixed := mixed * 10 - ENTIER(z);
  r := 3.5; x := 4.5D0; compare := 0;
  IF r < x THEN compare := compare * 10 + 1 ELSE compare := compare * 10 END;
  IF x = 4.5D0 THEN compare := compare * 10 + 1 ELSE compare := compare * 10 END;
  IF n > r THEN compare := compare * 10 + 1 ELSE compare := compare * 10 END;
  IF r # 3.5 THEN compare := compare * 10 + 1 ELSE compare := compare * 10 END;
  IF -x <= -4.5 THEN compare := compare * 10 + 1 ELSE compare := compare * 10 END;
  IF x >= n THEN compare := compare * 10 + 1 ELSE compare := compare * 10 END;
  x := 2.5D0; y := -2.5D0; z := -3.0D0; r := -1.25;
  floor := (ENTIER(x) + 5) * 10000 + (ENTIER(y) + 5) * 1000 + (ENTIER(z) + 5) * 100 + (ENTIER(x - 3) + 5) * 10
    + ENTIER(r) + 5;
  x := 0.1D0; r := SHORT(x); y := LONG(r);
  conv := ENTIER((y - x) * 1.0D10) * 10000 + ENTIER(ABS(z - 10)) * 100 + ENTIER(ABS(r - 3) * 4);
  y := 9; x := 1.25; Twice(x); f := Half;
  params := ENTIER(Half(y) * 10) * 100000 + ENTIER(Scale(1.5, 3)) * 10000 + ENTIER(x * 10) * 100 + ENTIER(f(10));
  params := params * 100 + ENTIER(y * 2 + Half(y));
  p.x := 1.5; p.y := p.x * 2; p.w := SHORT(p.y + 0.25);
  FOR n := 0 TO 2 DO a[n] := n * 1.5D0 + 1 END;
  fields := ENTIER(Sum(a) * 10) * 100 + ENTIER(p.w * 4);
  spill := ENTIER(Spilled());
  h := 12345678901234; x := h; h := -h; y := h;
  wide := ENTIER(x / 1.0D6) * 100 + ENTIER(y / 1.0D6) + 12345680;
  h := 9007199254740993; x := h; y := 9007199254740992.0D0; z := y + 1;
  tie := ENTIER(x - y) * 10 + ENTIER(z - y);
  IF mode = 1 THEN z := 3.0D9; l := ENTIER(z) END;
  IF mode = 2 THEN x := x / zero END
END VaxReals.
