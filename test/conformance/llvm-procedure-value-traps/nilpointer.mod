MODULE nilpointer;
  (* PLAN.md Phase 9 step 8: reaching a procedure field through a NIL pointer (the dereference traps, not the call). Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    m: Machine; n: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  SysWrite(1, "A", 1);
  n := m.op(1, 2);
  SysWrite(1, "B", 1)
END nilpointer.
