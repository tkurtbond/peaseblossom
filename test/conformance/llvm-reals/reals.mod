MODULE reals;
  (* PLAN.md Phase 9 step 2's compile+link+run+diff fixture for REAL/
     LONGREAL: arithmetic (+ - * and real division, including "/" on two
     integer operands, which is a real division), comparisons (all six
     relations, REAL against LONGREAL, integer against real), unary
     minus, ABS, LONG/SHORT between REAL and LONGREAL and between the
     integer types, ENTIER's floor semantics (a negative non-integral
     argument rounds down, not toward zero), real literals and CONSTs
     (a numeral echoed as written, a computed CONST emitted as its own
     bit pattern), REAL/LONGREAL through array elements, record fields,
     value and VAR parameters and function results, integer-to-real
     conversion on assignment/argument/return, and DIV/MOD staying
     integer-only. Each check prints "FAIL nn " on failure and the
     whole run ends with "OK" if nothing did.

     Every expected value is either exactly representable or a
     deliberately chosen rounding case: 0.1D0 + 0.2D0 > 0.3D0 and
     0.1D0 * 10.0D0 = 1.0D0 only hold if the literals are correctly
     rounded doubles, and LONG(0.1) = 0.10000000149011612D0 only if the
     REAL literal 0.1 is the nearest single-precision value - the very
     numbers ConstantEvaluator.ParseReal (not correctly rounded, see its
     header comment) gets slightly wrong, which is why a numeral is
     echoed as text instead of emitted from its folded value.

     Cross-checked against real voc (SysWrite swapped for Out.String):
     every check passes there except 27, 44 and 51 - not a poc
     disagreement, voc's own C output is what goes wrong: it prints
     each REAL constant into its generated C with 8 significant digits
     and each LONGREAL one with 15 (`1.0000000e-001`,
     `1.00000001490116e-001`), which a C compiler then reads back as a
     different double, so anything comparing a single-precision value
     against a decimal-spelled one, or spelling a LONG(REAL) double out
     in full, compares unequal. Those three are exactly the
     single-precision-rounding checks. *)
  CONST
    half = 0.5;
    scale = 2.0 * 1.5;
    neg = -2.5;
    third = 1.0D0 / 3.0D0;
    rthird = 1.0 / 3.0;
    tiny = 1.0D0 / 1.0D300;
  VAR
    r: REAL;
    d, d2: LONGREAL;
    i, loops: INTEGER;
    li: LONGINT;
    a: ARRAY 3 OF LONGREAL;
    rec: RECORD x: REAL; y: LONGREAL END;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Half(x: REAL): REAL;
  BEGIN
    RETURN x / 2
  END Half;

  PROCEDURE Mid(a, b: LONGREAL): LONGREAL;
  BEGIN
    RETURN (a + b) / 2.0D0
  END Mid;

  PROCEDURE Widen(x: REAL): LONGREAL;
  BEGIN
    RETURN x
  END Widen;

  PROCEDURE Scale(x: LONGREAL; n: INTEGER): LONGREAL;
  BEGIN
    RETURN x * n
  END Scale;

  PROCEDURE Bump(VAR x: LONGREAL);
  BEGIN
    x := x + 1
  END Bump;

BEGIN
  r := 1.5; d := 2.25D0; i := 3; li := 12345;
  IF ~(r + 1.0 = 2.5) THEN SysWrite(1, "FAIL 01 ", 8) END;
  IF ~(r * 2 = 3.0) THEN SysWrite(1, "FAIL 02 ", 8) END;
  IF ~(r - 0.5 = 1.0) THEN SysWrite(1, "FAIL 03 ", 8) END;
  IF ~(d / 4 = 0.5625D0) THEN SysWrite(1, "FAIL 04 ", 8) END;
  IF ~(7 / 2 = 3.5) THEN SysWrite(1, "FAIL 05 ", 8) END;
  IF ~(i / 2 = 1.5) THEN SysWrite(1, "FAIL 06 ", 8) END;
  IF ~(7 DIV 2 = 3) THEN SysWrite(1, "FAIL 07 ", 8) END;
  IF ~(7 MOD 2 = 1) THEN SysWrite(1, "FAIL 08 ", 8) END;
  IF ~((-7) DIV 2 = -4) THEN SysWrite(1, "FAIL 09 ", 8) END;
  IF ~(r < 2.5) THEN SysWrite(1, "FAIL 10 ", 8) END;
  IF ~(r <= 1.5) THEN SysWrite(1, "FAIL 11 ", 8) END;
  IF ~(r > 1.0) THEN SysWrite(1, "FAIL 12 ", 8) END;
  IF ~(r >= 1.5) THEN SysWrite(1, "FAIL 13 ", 8) END;
  IF ~(r # 2.0) THEN SysWrite(1, "FAIL 14 ", 8) END;
  IF ~(r = 1.5) THEN SysWrite(1, "FAIL 15 ", 8) END;
  IF ~(i < 3.5) THEN SysWrite(1, "FAIL 16 ", 8) END;
  IF ~(i = 3.0) THEN SysWrite(1, "FAIL 17 ", 8) END;
  IF ~(d > r) THEN SysWrite(1, "FAIL 18 ", 8) END;
  IF ~(-r = -1.5) THEN SysWrite(1, "FAIL 19 ", 8) END;
  IF ~(-d < 0.0D0) THEN SysWrite(1, "FAIL 20 ", 8) END;
  IF ~(ABS(-2.5) = 2.5) THEN SysWrite(1, "FAIL 21 ", 8) END;
  IF ~(ABS(-d) = 2.25D0) THEN SysWrite(1, "FAIL 22 ", 8) END;
  IF ~(ABS(d) = d) THEN SysWrite(1, "FAIL 23 ", 8) END;
  IF ~(LONG(r) = 1.5D0) THEN SysWrite(1, "FAIL 24 ", 8) END;
  IF ~(SHORT(d) = 2.25) THEN SysWrite(1, "FAIL 25 ", 8) END;
  IF ~(LONG(0.1) = 0.10000000149011612D0) THEN SysWrite(1, "FAIL 26 ", 8) END;
  IF ~(SHORT(0.1D0) = 0.1) THEN SysWrite(1, "FAIL 27 ", 8) END;
  IF ~(SHORT(li) = 12345) THEN SysWrite(1, "FAIL 28 ", 8) END;
  IF ~(LONG(i) = 3) THEN SysWrite(1, "FAIL 29 ", 8) END;
  IF ~(ENTIER(2.75) = 2) THEN SysWrite(1, "FAIL 30 ", 8) END;
  IF ~(ENTIER(-2.75) = -3) THEN SysWrite(1, "FAIL 31 ", 8) END;
  IF ~(ENTIER(-3.0) = -3) THEN SysWrite(1, "FAIL 32 ", 8) END;
  IF ~(ENTIER(-0.5D0) = -1) THEN SysWrite(1, "FAIL 33 ", 8) END;
  IF ~(ENTIER(1000.25D0) = 1000) THEN SysWrite(1, "FAIL 34 ", 8) END;
  IF ~(0.1D0 + 0.2D0 > 0.3D0) THEN SysWrite(1, "FAIL 35 ", 8) END;
  IF ~(0.1D0 * 10.0D0 = 1.0D0) THEN SysWrite(1, "FAIL 36 ", 8) END;
  IF ~(1.5E3 = 1500.0) THEN SysWrite(1, "FAIL 37 ", 8) END;
  IF ~(2.5D-1 = 0.25D0) THEN SysWrite(1, "FAIL 38 ", 8) END;
  IF ~(1.0D2 = 100.0D0) THEN SysWrite(1, "FAIL 39 ", 8) END;
  IF ~(half + half = 1.0) THEN SysWrite(1, "FAIL 40 ", 8) END;
  IF ~(scale = 3.0) THEN SysWrite(1, "FAIL 41 ", 8) END;
  IF ~(neg + 2.5 = 0.0) THEN SysWrite(1, "FAIL 42 ", 8) END;
  IF ~(third * 3.0D0 = 1.0D0) THEN SysWrite(1, "FAIL 43 ", 8) END;
  IF ~(LONG(rthird) # third) THEN SysWrite(1, "FAIL 44 ", 8) END;
  IF ~(rthird * 3.0 = 1.0) THEN SysWrite(1, "FAIL 45 ", 8) END;
  IF ~((tiny > 0.0D0) & (tiny * 1.0D300 > 0.5D0)) THEN SysWrite(1, "FAIL 46 ", 8) END;
  a[1] := 2.5D0; a[0] := a[1] * 2; a[2] := 3;
  IF ~((a[0] = 5.0D0) & (a[1] = 2.5D0) & (a[2] = 3.0D0)) THEN SysWrite(1, "FAIL 47 ", 8) END;
  rec.x := 1.5; rec.y := rec.x;
  IF ~(rec.y = 1.5D0) THEN SysWrite(1, "FAIL 48 ", 8) END;
  IF ~(Half(3) = 1.5) THEN SysWrite(1, "FAIL 49 ", 8) END;
  IF ~(Mid(1, 2) = 1.5D0) THEN SysWrite(1, "FAIL 50 ", 8) END;
  IF ~(Widen(0.1) = 0.10000000149011612D0) THEN SysWrite(1, "FAIL 51 ", 8) END;
  IF ~(Scale(1.5D0, 4) = 6.0D0) THEN SysWrite(1, "FAIL 52 ", 8) END;
  Bump(d);
  IF ~(d = 3.25D0) THEN SysWrite(1, "FAIL 53 ", 8) END;
  d2 := 0.0D0; loops := 0;
  WHILE d2 < 3.0D0 DO d2 := d2 + 0.5D0; INC(loops) END;
  IF ~((loops = 6) & (d2 = 3.0D0)) THEN SysWrite(1, "FAIL 54 ", 8) END;
  i := 6; li := 12345; r := i; d := li;
  IF ~((r = 6.0) & (d = 12345.0D0)) THEN SysWrite(1, "FAIL 55 ", 8) END;
  r := 1.5; d := 0.25D0;
  IF ~(r + d = 1.75D0) THEN SysWrite(1, "FAIL 56 ", 8) END;
  SysWrite(1, "OK", 2)
END reals.
