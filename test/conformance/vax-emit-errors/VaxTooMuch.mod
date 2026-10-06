MODULE VaxTooMuch;
  (* PLAN.md Phase 15 steps 2-3: what the VAX backend cannot lower yet,
     each reported at its position - an import (step 8), an array
     variable (step 6), a procedure (step 5), a structured statement (step
     4), a predeclared function (step 7), HUGEINT multiplication (a call
     to the runtime, step 5) - and no .mar is left, not even the imported
     module's, which alone could be written *)
  IMPORT VaxImported;
  VAR a: ARRAY 2 OF INTEGER; i: INTEGER; c: CHAR; h: HUGEINT;
  PROCEDURE P; END P;
BEGIN
  IF i = 0 THEN i := 1 END;
  i := ORD(c);
  h := h * h
END VaxTooMuch.
