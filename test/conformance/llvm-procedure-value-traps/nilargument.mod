MODULE nilargument;
  (* PLAN.md Phase 9 step 8: a NIL passed for a procedure parameter, then called. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

  PROCEDURE Apply(op: Binary; a, b: INTEGER): INTEGER;
  BEGIN RETURN op(a, b) END Apply;

BEGIN
  SysWrite(1, "A", 1);
  n := Apply(NIL, 1, 2);
  SysWrite(1, "B", 1)
END nilargument.
