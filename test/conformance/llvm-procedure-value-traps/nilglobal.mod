MODULE nilglobal;
  (* PLAN.md Phase 9 step 8: calling a procedure variable that is still NIL. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  IMPORT Out;
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    f: Binary; n: INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  Out.String("A");
  n := f(1, 2);
  Out.String("B")
END nilglobal.
