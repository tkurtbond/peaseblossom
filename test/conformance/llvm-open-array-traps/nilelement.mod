MODULE nilelement;
  (* PLAN.md Phase 9 step 7: indexing a NIL pointer to an open array. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  v := NIL;
  v[0] := 1;
  SysWrite(1, "B", 1)
END nilelement.
