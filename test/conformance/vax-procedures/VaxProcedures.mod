MODULE VaxProcedures;
  (* PLAN.md Phase 15 step 5: procedures. An exported one is .ENTRY, a
     private one a local label and .WORD of its mask (decided with the
     user 2026-10-06). Locals live below FP, cleared on entry - CLRQ and
     CLRL, or MOVC5 for a larger frame - with the slots for spills and
     argument lists below them. A function returns its value in R0 as a
     longword, a HUGEINT in R0 and R1; one that reaches its END traps
     (code 12) *)

  VAR count*: INTEGER;

  PROCEDURE Tick*;
  BEGIN
    count := count + 1
  END Tick;

  PROCEDURE Sign(x: LONGINT): SHORTINT;
  BEGIN
    IF x < 0 THEN RETURN -1 ELSIF x > 0 THEN RETURN 1 END;
    RETURN 0
  END Sign;

  PROCEDURE IsDigit(ch: CHAR): BOOLEAN;
  BEGIN
    RETURN (ch >= "0") & (ch <= "9")
  END IsDigit;

  PROCEDURE Total(n: INTEGER): HUGEINT;
    VAR i: INTEGER; sum: HUGEINT;
  BEGIN
    FOR i := 1 TO n DO sum := sum + i END;
    RETURN sum
  END Total;

  PROCEDURE Many(): LONGINT;
    VAR a, b, c, d, e, f, g, h, i, j, k, l, m, n, o, p, q: LONGINT;
  BEGIN
    a := 1; q := a;
    RETURN q
  END Many;

  PROCEDURE Last(): CHAR;
  BEGIN
    IF count > 0 THEN RETURN "x" END
  END Last;

END VaxProcedures.
