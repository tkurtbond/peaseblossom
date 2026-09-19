MODULE nilelement;
  (* PLAN.md Phase 9 step 8: calling a NIL element of an array of procedures. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    table: ARRAY 3 OF Binary; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  SysWrite(1, "A", 1);
  table[0] := Add;
  n := table[1](1, 2);
  SysWrite(1, "B", 1)
END nilelement.
