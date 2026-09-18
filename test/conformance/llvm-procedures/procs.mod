MODULE procs;
  (* PLAN.md Phase 8 step 10's dedicated compile+link+run+diff-stdout
     fixture for ordinary (non-external, non-type-bound) procedure
     codegen: value vs. VAR parameter passing, local (alloca-backed)
     storage, RETURN with a value, one procedure calling another
     (including a recursive call), and a VAR argument reached through a
     selector chain (a record field, an array element - GenerateVarArg-
     Value now delegates to GenerateDesignatorAddress, step 8's own
     address computation, rather than only accepting a bare VAR).
     Values are proven correct the same way steps 7/8's own runtime
     fixtures are: branch on a computed result and print one of two
     literal markers - see procs-ir for the same constructs verified by
     directly inspecting computed values via the C-harness technique
     instead. *)
  TYPE
    Point = RECORD x, y: INTEGER END;
  VAR
    total: INTEGER;
    p: Point;
    v: ARRAY 3 OF INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Add(a, b: INTEGER): INTEGER;
    VAR sum: INTEGER;
  BEGIN
    sum := a + b;
    RETURN sum
  END Add;

  PROCEDURE Increment(VAR x: INTEGER; by: INTEGER);
  BEGIN
    x := x + by
  END Increment;

  (* Recursive call, and a function procedure whose every path DOES
     return a value (unlike MaybeReturn below) - the ordinary,
     well-formed case. *)
  PROCEDURE Fact(n: INTEGER): INTEGER;
  BEGIN
    IF n <= 1 THEN RETURN 1 ELSE RETURN n * Fact(n - 1) END
  END Fact;

  (* A function procedure whose ELSE-less IF leaves a path with no
     RETURN at all - real, front-end-accepted Oberon-2 (Semantic-
     Actions.CheckProcedureBody's own "function procedure must return
     a value" check is deliberately shallow, not full reachability
     analysis). GenerateProcedureDecl's own trailing "ret <type> 0"
     fallback is what keeps this well-defined (if not meaningful)
     rather than miscompiled. *)
  PROCEDURE MaybeReturn(n: INTEGER): INTEGER;
  BEGIN
    IF n > 0 THEN RETURN n * 2 END
  END MaybeReturn;

BEGIN
  total := Add(3, 4);
  Increment(total, 10);
  total := total + Fact(5);
  total := total + MaybeReturn(6) + MaybeReturn(-1);

  p.x := 1; p.y := 2;
  Increment(p.x, 1);
  v[1] := 0;
  Increment(v[1], 5);

  IF (total = 149) & (p.x = 2) & (v[1] = 5) THEN SysWrite(1, "OK", 2) ELSE SysWrite(1, "FAIL", 4) END
END procs.
