MODULE overflow;
  (* What poc promises where Oberon2.pdf defines nothing (Phase 11, C5;
     doc/overflow-survey.md): integer + - * and unary -, ABS, INC and DEC that
     leave the type's range wrap around at the type's own width, DIV and MOD
     of a non-zero divisor floor, and real arithmetic is IEEE and silent -
     overflow is an infinity, 0.0/0.0 a NaN, underflow a zero, a division by
     zero an infinity, and nothing traps.  voc does the same, so test.sh runs
     this source under both compilers and both size models and requires the
     same output.  The widths follow the model (SHORTINT is 8 bits under -O2,
     16 under -OC, ...), so the two models print different numbers. *)
  IMPORT Out;

  VAR
    s: SHORTINT; i: INTEGER; l: LONGINT; h: HUGEINT; m, d: LONGINT;
    x, y, z: LONGREAL; r, q: REAL;

  PROCEDURE Line(label: ARRAY OF CHAR; a, b, c, e: HUGEINT);
  BEGIN
    Out.String(label); Out.Char(" ");
    Out.Int(a, 0); Out.Char(" "); Out.Int(b, 0); Out.Char(" ");
    Out.Int(c, 0); Out.Char(" "); Out.Int(e, 0); Out.Ln
  END Line;

  PROCEDURE Verdict(label: ARRAY OF CHAR; text: ARRAY OF CHAR);
  BEGIN Out.String(label); Out.Char(" "); Out.String(text); Out.Ln END Verdict;

  PROCEDURE Integers;
    VAR sa, sb, sc, sd: SHORTINT; ia, ib, ic, id: INTEGER; la, lb, lc, ld: LONGINT; ha, hb, hc, hd: HUGEINT;
  BEGIN
    (* MAX+1, MIN-1, MAX*2, -MIN, one line per type; variables, so nothing folds *)
    m := 2;
    s := MAX(SHORTINT); sa := s + 1; s := MIN(SHORTINT); sb := s - 1;
    s := MAX(SHORTINT); sc := s * SHORT(SHORT(m)); s := MIN(SHORTINT); sd := -s;
    Line("SHORTINT", sa, sb, sc, sd);
    i := MAX(INTEGER); ia := i + 1; i := MIN(INTEGER); ib := i - 1;
    i := MAX(INTEGER); ic := i * SHORT(m); i := MIN(INTEGER); id := -i;
    Line("INTEGER ", ia, ib, ic, id);
    l := MAX(LONGINT); la := l + 1; l := MIN(LONGINT); lb := l - 1;
    l := MAX(LONGINT); lc := l * m; l := MIN(LONGINT); ld := -l;
    Line("LONGINT ", la, lb, lc, ld);
    h := MAX(HUGEINT); ha := h + 1; h := MIN(HUGEINT); hb := h - 1;
    h := MAX(HUGEINT); hc := h * m; h := MIN(HUGEINT); hd := -h;
    Line("HUGEINT ", ha, hb, hc, hd);
    (* ABS, INC and DEC at the ends *)
    s := MIN(SHORTINT); sa := ABS(s); i := MIN(INTEGER); ia := ABS(i);
    l := MIN(LONGINT); la := ABS(l); h := MIN(HUGEINT); ha := ABS(h);
    Line("ABS(MIN)", sa, ia, la, ha);
    s := MAX(SHORTINT); INC(s); i := MAX(INTEGER); INC(i); l := MAX(LONGINT); INC(l); h := MAX(HUGEINT); INC(h);
    Line("INC(MAX)", s, i, l, h);
    s := MIN(SHORTINT); DEC(s); i := MIN(INTEGER); DEC(i); l := MIN(LONGINT); DEC(l); h := MIN(HUGEINT); DEC(h);
    Line("DEC(MIN)", s, i, l, h)
  END Integers;

  PROCEDURE Divisions;
    VAR a, b: LONGINT;
  BEGIN
    (* floored, whatever the signs: 7 DIV -2, 7 MOD -2, -7 DIV 2, -7 MOD 2 *)
    a := 7; b := -2; m := a DIV b; d := a MOD b;
    a := -7; b := 2;
    Line("DIV/MOD ", m, d, a DIV b, a MOD b)
  END Divisions;

  PROCEDURE Reals;
  BEGIN
    x := 1.0D0; y := 0.0D0; z := x / y;
    IF z > 1.0D300 THEN Verdict("1/0", "infinity") ELSE Verdict("1/0", "finite") END;
    x := 0.0D0; z := x / y;
    IF z = z THEN Verdict("0/0", "number") ELSE Verdict("0/0", "NaN") END;
    x := 1.0D300; y := 1.0D300; z := x * y;
    IF z > 1.0D300 THEN Verdict("LONGREAL 1e300*1e300", "infinity") ELSE Verdict("LONGREAL 1e300*1e300", "finite") END;
    x := 1.0D-300; y := 1.0D-300; z := x * y;
    IF z = 0.0D0 THEN Verdict("LONGREAL 1e-300*1e-300", "zero") ELSE Verdict("LONGREAL 1e-300*1e-300", "nonzero") END;
    r := 1.0E30; q := r * r;
    IF q > 9.0E37 THEN Verdict("REAL 1e30*1e30", "infinity") ELSE Verdict("REAL 1e30*1e30", "finite") END;
    r := 1.0E-30; q := r * r;
    IF q = 0.0E0 THEN Verdict("REAL 1e-30*1e-30", "zero") ELSE Verdict("REAL 1e-30*1e-30", "nonzero") END;
    r := 1.0E0; q := 0.0E0; z := r / q;
    IF z > 1.0D300 THEN Verdict("REAL 1/0", "infinity") ELSE Verdict("REAL 1/0", "finite") END;
    x := 1.0D300; r := SHORT(x);
    IF r > 9.0E37 THEN Verdict("SHORT(1e300)", "infinity") ELSE Verdict("SHORT(1e300)", "finite") END
  END Reals;

BEGIN
  Integers;
  Divisions;
  Reals
END overflow.
