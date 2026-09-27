MODULE strict;
  (* poc -strict (Phase 11 B2): each line from the first TYPE on uses one
     extension beyond Oberon2.pdf, and -strict reports it; without -strict
     the module is accepted. The procedure at the end uses only the report
     (SYSTEM's own Appendix C part included) and is never reported. *)
  IMPORT SYSTEM;
  CONST
    big = 10000000000;
    wide = {0, 40};
    pattern = 0FFFFFFFFFFFFFFFFH;
  TYPE
    H = HUGEINT;
    A = SYSTEM.ADDRESS;
    I = SYSTEM.INT32;
    S = SYSTEM.SET64;
    P = POINTER TO RECORD x: INTEGER END;
  VAR
    h: HUGEINT; i: INTEGER; l: LONGINT; s: SET; b: BOOLEAN;
    small: ARRAY 4 OF CHAR; large: ARRAY 8 OF CHAR;
    any: SYSTEM.PTR; p: P; c: CHAR;

  PROCEDURE ["C", "abs"] CAbs(x: SYSTEM.INT32): SYSTEM.INT32;

  PROCEDURE Plain(VAR buf: ARRAY OF SYSTEM.BYTE; q: P): LONGINT;
    VAR a: LONGINT; k: SHORTINT;
  BEGIN
    a := SYSTEM.ADR(buf); k := SYSTEM.VAL(SHORTINT, c);
    k := SYSTEM.LSH(k, 1); any := q;
    IF SYSTEM.BIT(a, 0) THEN INC(k) END;
    RETURN a + ORD(c) + MAX(LONGINT) - SIZE(P)
  END Plain;

BEGIN
  ASSERT(TRUE);
  i := ORD(s);
  large := small;
  b := any = p;
  h := 100000 * 100000;
  b := 3 IN {i, 40};
  h := MAX(HUGEINT);
  l := 0FFFFFFFFD76AA478H + l
END strict.
