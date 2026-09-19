MODULE pointerindex;
  (* PLAN.md Phase 9 step 7: an index one past the end of a pointer to an open array. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR at: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
BEGIN
  SysWrite(1, "A", 1);
  at := 4;
  NEW(v, 4);
  v[at] := 1;
  SysWrite(1, "B", 1)
END pointerindex.
