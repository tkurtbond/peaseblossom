MODULE VaxTooMuch;
  (* PLAN.md Phase 15 steps 2-7: what the VAX backend cannot lower yet,
     each reported at its position - an import (step 8), an array of REAL
     (Phase 16), a ["C"] external procedure (VAX/VMS takes "VMS"),
     a nested procedure, a type-bound one and an open array parameter
     (Phase 16), ASSERT (outside the slice), a procedure as a value
     (Phase 16) - and no .mar is left, not even the imported module's,
     which alone could be written *)
  IMPORT VaxImported;
  TYPE R = RECORD END;
  VAR a: ARRAY 2 OF REAL; i: INTEGER; l: LONGINT;
  PROCEDURE ["C", "abs"] Abs(x: LONGINT): LONGINT;
  PROCEDURE Outer; PROCEDURE Inner; END Inner; BEGIN Inner END Outer;
  PROCEDURE (VAR r: R) Method; END Method;
  PROCEDURE Sum(x: ARRAY OF INTEGER): INTEGER; BEGIN RETURN 0 END Sum;
  PROCEDURE P; END P;
  PROCEDURE Q(p: PROCEDURE); END Q;
BEGIN
  IF i = 0 THEN P END;
  ASSERT(l > 0);
  Q(P)
END VaxTooMuch.
