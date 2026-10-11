MODULE nilproper;
  (* PLAN.md Phase 9 step 8: calling a NIL procedure variable of a proper procedure type, as a statement. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  IMPORT Out;
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    act: Action;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  Out.String("A");
  act;
  Out.String("B")
END nilproper.
