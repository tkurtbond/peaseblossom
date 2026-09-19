MODULE nilproper;
  (* PLAN.md Phase 9 step 8: calling a NIL procedure variable of a proper procedure type, as a statement. Prints "A", then must trap
     (NIL access, exit 4) before it can print "B". *)
  TYPE
    Binary = PROCEDURE (a, b: INTEGER): INTEGER;
    Action = PROCEDURE;
    Machine = POINTER TO MachineDesc;
    MachineDesc = RECORD op: Binary END;
  VAR
    act: Action;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);

  PROCEDURE Add(a, b: INTEGER): INTEGER;
  BEGIN RETURN a + b END Add;

BEGIN
  SysWrite(1, "A", 1);
  act;
  SysWrite(1, "B", 1)
END nilproper.
