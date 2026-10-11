MODULE nilfield;
  (* PLAN.md Phase 9 step 8: calling a NIL procedure field of a record on the heap. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  IMPORT Out;
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    m: Machine; n: INTEGER;

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  Out.String("A");
  NEW(m);
  n := m.op(1, 2);
  Out.String("B")
END nilfield.
