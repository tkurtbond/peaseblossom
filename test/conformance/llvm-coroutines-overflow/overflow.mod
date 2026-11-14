MODULE overflow;
  (* A recursion with no end on a coroutine of the smallest stack runs
     into its guard page. *)
  IMPORT SYSTEM, Coroutines, Out;

  VAR main, worker: Coroutines.Coroutine; total: LONGINT; frame: SYSTEM.ADDRESS;

  (* each frame's address escapes, and the result indexes it, so that the
     optimizer can make no loop of the recursion *)
  PROCEDURE Deeper(n: LONGINT): LONGINT;
    VAR filler: ARRAY 32 OF LONGINT; result: LONGINT;
  BEGIN
    filler[n MOD 32] := n;
    frame := SYSTEM.ADR(filler);
    result := Deeper(n + 1);
    RETURN filler[result MOD 32] + 1
  END Deeper;

  PROCEDURE Recurse;
  BEGIN
    total := Deeper(0);
    LOOP Coroutines.Transfer(worker, main) END
  END Recurse;

BEGIN
  Out.String("recursing on a coroutine"); Out.Ln;
  Coroutines.Init(Recurse, 0, worker);
  Coroutines.Transfer(main, worker);
  Out.String("not reached "); Out.Int(total, 0); Out.Ln
END overflow.
