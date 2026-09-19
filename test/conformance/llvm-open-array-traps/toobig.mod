MODULE toobig;
  (* PLAN.md Phase 9 step 7: NEW of more than the heap will supply: NIL, not a trap. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  n := 1000000000;
  NEW(v, n);
  IF v = NIL THEN SysWrite(1, "N", 1) END;
  SysWrite(1, "B", 1)
END toobig.
