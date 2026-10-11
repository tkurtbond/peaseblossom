MODULE nilargument;
  (* PLAN.md Phase 9 step 8: a NIL passed for a procedure parameter, then called. Prints "A", then must trap
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

  PROCEDURE Apply(op: Binary; a, b: INTEGER): INTEGER;
  BEGIN RETURN op(a, b) END Apply;

BEGIN
  Out.String("A");
  n := Apply(NIL, 1, 2);
  Out.String("B")
END nilargument.
