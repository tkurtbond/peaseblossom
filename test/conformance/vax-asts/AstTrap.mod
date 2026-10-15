MODULE AstTrap;

  (* Phase 17 step 6 (doc/developer/vax-macro32-backend.md, section 22.3,
     proposals 3 and 8): a trap at AST level ends the program as anywhere,
     with its message and status, and Out's line before it is written *)

  IMPORT SYSTEM, Out, Timers;

  VAR table: ARRAY 4 OF INTEGER; index: INTEGER;

  PROCEDURE Fault(parameter: SYSTEM.CARD32);
  BEGIN
    table[index] := 1
  END Fault;

BEGIN
  index := 4;
  Out.String("before the AST"); Out.Ln;
  IF Timers.After(20, Fault, 1) = 1 THEN END;
  IF Timers.Sleep(500) = 1 THEN END;
  Out.String("not reached"); Out.Ln
END AstTrap.
