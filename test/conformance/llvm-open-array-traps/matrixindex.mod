MODULE matrixindex;
  (* PLAN.md Phase 9 step 7: an index past the inner dimension of a two-dimensional open array. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR m: POINTER TO ARRAY OF ARRAY OF INTEGER; at: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  at := 5;
  NEW(m, 3, 5);
  m[2, at] := 1;
  SysWrite(1, "B", 1)
END matrixindex.
