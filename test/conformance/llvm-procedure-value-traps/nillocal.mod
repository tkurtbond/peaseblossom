MODULE nillocal;
  (* PLAN.md Phase 9 step 8: calling a *local* procedure variable that was never assigned - poc zeroes it, like a local pointer (voc leaves it as stack garbage). Prints "A", then must trap
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

  PROCEDURE Broken(): INTEGER;
    VAR f: Binary;
  BEGIN RETURN f(1, 2) END Broken;

BEGIN
  SysWrite(1, "A", 1);
  n := Broken();
  SysWrite(1, "B", 1)
END nillocal.
