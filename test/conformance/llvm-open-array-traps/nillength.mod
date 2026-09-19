MODULE nillength;
  (* PLAN.md Phase 9 step 7: LEN of a NIL pointer to an open array's target. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  v := NIL;
  n := LEN(v^);
  SysWrite(1, "B", 1)
END nillength.
