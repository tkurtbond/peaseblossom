MODULE VaxArrays;
  (* PLAN.md Phase 15 step 6: arrays. A constant index is a displacement,
     checked by the compiler. Any other is checked at run time - CMPL with
     LEN - 1 and an unsigned branch, so a negative index fails too, over
     the index trap (POC_TRAP, code 2, at the index) - then, for an
     element of 1, 2 or 4 bytes, used by index mode, base[Rx], which
     scales it by the element's size; for a HUGEINT or an array element
     scaled by MULL2 and the element's address made by MOVAB (decided with
     the user 2026-10-06). A whole array is copied by MOVC3. *)

  VAR
    a: ARRAY 10 OF INTEGER;
    b: ARRAY 4 OF CHAR;
    f: ARRAY 3 OF BOOLEAN;
    s: ARRAY 5 OF SET;
    h: ARRAY 3 OF HUGEINT;
    m: ARRAY 3, 4 OF INTEGER;
    c: ARRAY 10 OF INTEGER;
    i, j: INTEGER; k: SHORTINT; n: LONGINT; q: HUGEINT;
    x: INTEGER; ch: CHAR; t: SET;

  PROCEDURE Inc(VAR v: INTEGER);
  BEGIN
    v := v + 1
  END Inc;

BEGIN
  a[3] := 7;
  a[i] := a[j] + 1;
  x := a[k];
  b[n] := "x";
  ch := b[i];
  h[i] := q;
  q := h[2] + h[j];
  m[i, j] := 5;
  m[1][j] := m[i, 2];
  IF f[i] THEN x := 1 END;
  IF i IN s[j] THEN x := 2 END;
  t := {a[i]};
  a[q] := 0;
  c := a;
  Inc(a[i]);
  Inc(m[i, j])
END VaxArrays.
