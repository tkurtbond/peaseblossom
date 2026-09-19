MODULE zerolength;
  (* PLAN.md Phase 9 step 7: NEW with a length of zero (voc traps too). Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  n := 0;
  NEW(v, n);
  SysWrite(1, "B", 1)
END zerolength.
