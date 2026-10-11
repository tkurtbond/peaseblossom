MODULE nilpointer;
  (* PLAN.md Phase 9 step 8: reaching a procedure field through a NIL pointer (the dereference traps, not the call). Prints "A", then must trap
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
  n := m.op(1, 2);
  Out.String("B")
END nilpointer.
