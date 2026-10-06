MODULE VaxCalls;
  (* PLAN.md Phase 15 step 5: calls. The arguments are evaluated left to
     right, each stored in an argument list in the caller's frame, then
     CALLG (decided with the user 2026-10-06); CALLS #0 without
     arguments. A value of a longword or less is passed sign- or
     zero-extended to a longword, a HUGEINT as the address of a copy, a
     VAR argument as its variable's address. R2-R5 survive a call, R0
     and R1 do not: a value there is moved up before the call. HUGEINT *,
     DIV and MOD are calls of poc's runtime. A procedure may call
     itself: each activation builds its argument lists in its own frame *)

  VAR i, j: INTEGER; l: LONGINT; h, k: HUGEINT; c: CHAR; ok: BOOLEAN;

  PROCEDURE Max(a, b: INTEGER): INTEGER;
  BEGIN
    IF a > b THEN RETURN a END;
    RETURN b
  END Max;

  PROCEDURE Next(): LONGINT;
  BEGIN
    l := l + 1;
    RETURN l
  END Next;

  PROCEDURE Put(ch: CHAR; done: BOOLEAN; VAR count: INTEGER);
  BEGIN
    IF done THEN count := count + 1 END
  END Put;

  PROCEDURE Add(x, y: HUGEINT): HUGEINT;
  BEGIN
    RETURN x + y
  END Add;

  PROCEDURE Fact(n: INTEGER): LONGINT;
  BEGIN
    IF n <= 1 THEN RETURN 1 END;
    RETURN n * Fact(n - 1)
  END Fact;

BEGIN
  i := Max(i, Max(j, 3));
  l := Next() - Next();
  Put(c, i > j, i);
  h := Add(h, l);
  ok := (i < j) & (Max(i, j) = 3);
  k := h * k + h DIV k - h MOD 10;
  l := Fact(j)
END VaxCalls.
