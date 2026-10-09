MODULE VaxProcLib;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 7): VaxProcVals's import - an exported procedure type, an
     exported procedure and a private one an importer takes as values, a
     variable of procedure type an importer calls and assigns, and a
     procedure calling the value it is given. *)
  TYPE
    Binary* = PROCEDURE (a, b: INTEGER): INTEGER;
  VAR
    op*: Binary; calls*: INTEGER;

  PROCEDURE Max*(a, b: INTEGER): INTEGER;
  BEGIN
    IF a > b THEN RETURN a ELSE RETURN b END
  END Max;

  PROCEDURE Twice(a, b: INTEGER): INTEGER;
  BEGIN RETURN 2 * (a + b)
  END Twice;

  PROCEDURE Hidden*(): Binary;
  BEGIN RETURN Twice
  END Hidden;

  PROCEDURE Apply*(f: Binary; a, b: INTEGER): INTEGER;
  BEGIN INC(calls); RETURN f(a, b)
  END Apply;

BEGIN
  op := Max
END VaxProcLib.
