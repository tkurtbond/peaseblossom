MODULE nilelement;
  (* PLAN.md Phase 9 step 8: calling a NIL element of an array of procedures. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  IMPORT Out;
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    table: ARRAY 3 OF Binary; n: INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  Out.String("A");
  table[0] := Add;
  n := table[1](1, 2);
  Out.String("B")
END nilelement.
