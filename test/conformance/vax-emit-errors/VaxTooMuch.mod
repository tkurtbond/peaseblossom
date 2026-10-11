MODULE VaxTooMuch;
  (* PLAN.md Phase 15 steps 2-8: what the VAX backend cannot lower yet,
     each at its position - an array of records with field initializers
     (Phase 16), a ["C"] external procedure (VAX/VMS takes "VMS"), an open
     array passed to an external (Phase 17), SYSTEM.VAL from a HUGEINT to
     a REAL (SYSTEM.GET, then SYSTEM.MOVE, were until Phase 16 steps 4 and
     5 lowered them) - and no .mar is left, not even the imported
     module's *)
  IMPORT SYSTEM, VaxImported;
  VAR a: ARRAY 2 OF RECORD n: INTEGER := 1 END; i: INTEGER; l: LONGINT; h: HUGEINT; x: REAL;
  PROCEDURE ["C", "abs"] Abs(x: LONGINT): LONGINT;
  PROCEDURE ["VMS"] EXT$SUM(VAR x: ARRAY OF INTEGER);
  PROCEDURE P; VAR v: ARRAY 2 OF INTEGER; BEGIN EXT$SUM(v) END P;
BEGIN
  IF i = 0 THEN P END;
  x := SYSTEM.VAL(REAL, h)
END VaxTooMuch.
