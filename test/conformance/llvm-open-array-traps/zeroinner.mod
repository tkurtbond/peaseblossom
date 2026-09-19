MODULE zeroinner;
  (* PLAN.md Phase 9 step 7: NEW with a zero length in the second dimension. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR m: POINTER TO ARRAY OF ARRAY OF INTEGER; n: LONGINT;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  n := 0;
  NEW(m, 3, n);
  SysWrite(1, "B", 1)
END zeroinner.
