MODULE ErrTrap;
  (* PLAN.md Phase 16 step 4: Err's line, then a trap, whose message goes
     to the error stream after it: on VAX/VMS through the one RMS stream
     both use (POC_ERR_OPEN) *)
  IMPORT Err;
  VAR p: POINTER TO RECORD n: INTEGER END;
BEGIN
  Err.String("before the trap"); Err.Ln;
  p := NIL;
  p.n := 1
END ErrTrap.
