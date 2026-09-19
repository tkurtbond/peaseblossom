MODULE paramindex;
  (* PLAN.md Phase 9 step 7: an index one past the end of an open-array parameter. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE Touch(VAR a: ARRAY OF INTEGER);
  BEGIN a[SHORT(LEN(a))] := 1 END Touch;
BEGIN
  SysWrite(1, "A", 1);
  NEW(v, 3);
  Touch(v^);
  SysWrite(1, "B", 1)
END paramindex.
