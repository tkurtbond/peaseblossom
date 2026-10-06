MODULE VaxTooMuch;
  (* PLAN.md Phase 15 step 2: what the VAX backend cannot lower yet, each
     reported at its position - an import (step 8), a variable and a
     statement (step 3), a procedure (step 5) - and no .mar is left, not
     even the imported module's, which alone could be written *)
  IMPORT VaxImported;
  VAR x: INTEGER;
  PROCEDURE P; END P;
BEGIN
  x := 1
END VaxTooMuch.
