MODULE procsir;
  (* PLAN.md Phase 8 step 10's dedicated golden-file fixture for
     ordinary-procedure codegen: value/VAR parameter passing, local
     (alloca-backed) storage, RETURN with a value, and a recursive
     call, verified by directly inspecting the computed values (the
     same C-harness linking technique steps 5/7/8 already established)
     rather than branching on them - see llvm-procedures for the same
     constructs exercised the other way, at runtime through the step 6
     write(2) FFI. This fixture's own final values were independently
     verified during development: total=137, p.x=2, v[1]=5. *)
  TYPE
    Point = RECORD x, y: INTEGER END;
  VAR
    total: INTEGER;
    p: Point;
    v: ARRAY 3 OF INTEGER;

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

  PROCEDURE Fact(n: INTEGER): INTEGER;
  BEGIN
    IF n <= 1 THEN RETURN 1 ELSE RETURN n * Fact(n - 1) END
  END Fact;

BEGIN
  total := Add(3, 4);
  Increment(total, 10);
  total := total + Fact(5);
  p.x := 1; p.y := 2;
  Increment(p.x, 1);
  v[1] := 0;
  Increment(v[1], 5)
END procsir.
