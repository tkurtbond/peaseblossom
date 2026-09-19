MODULE overflow;
  (* PLAN.md Phase 9 step 7: NEW whose size does not fit in 64 bits. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR m: POINTER TO ARRAY OF ARRAY OF INTEGER; n: HUGEINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  n := 5000000000;
  NEW(m, n, n);
  SysWrite(1, "B", 1)
END overflow.
