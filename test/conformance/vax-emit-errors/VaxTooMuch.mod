MODULE VaxTooMuch;
  (* PLAN.md Phase 15 steps 2-8: what the VAX backend cannot lower yet,
     each reported at its position - an array of REAL (Phase 16), a ["C"]
     external procedure (VAX/VMS takes "VMS"), a nested procedure, an open
     array passed to an external (Phase 17), ASSERT (outside the slice) -
     and no .mar is left, not even the imported module's, which alone
     could be written *)
  IMPORT VaxImported;
  VAR a: ARRAY 2 OF REAL; i: INTEGER; l: LONGINT;
  PROCEDURE ["C", "abs"] Abs(x: LONGINT): LONGINT;
  PROCEDURE Outer; PROCEDURE Inner; END Inner; BEGIN Inner END Outer;
  PROCEDURE ["VMS"] EXT$SUM(VAR x: ARRAY OF INTEGER);
  PROCEDURE P; VAR v: ARRAY 2 OF INTEGER; BEGIN EXT$SUM(v) END P;
BEGIN
  IF i = 0 THEN P END;
  ASSERT(l > 0)
END VaxTooMuch.
