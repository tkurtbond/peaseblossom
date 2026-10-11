MODULE nillocal;
  (* PLAN.md Phase 9 step 8: calling a *local* procedure variable that was never assigned - poc zeroes it, like a local pointer (voc leaves it as stack garbage). Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  IMPORT Out;
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    n: INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

  PROCEDURE Broken(): INTEGER;
    VAR f: Binary;
  BEGIN RETURN f(1, 2) END Broken;

BEGIN
  Out.String("A");
  n := Broken();
  Out.String("B")
END nillocal.
