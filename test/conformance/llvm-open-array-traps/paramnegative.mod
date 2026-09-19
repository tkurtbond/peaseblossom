MODULE paramnegative;
  (* PLAN.md Phase 9 step 7: a negative index into an open-array parameter. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR at: INTEGER;
  PROCEDURE ["C", "write"] SysWrite(fd: LONGINT; s: ARRAY OF CHAR; n: HUGEINT);
  PROCEDURE Touch(VAR a: ARRAY OF INTEGER; i: INTEGER);
  BEGIN a[i] := 1 END Touch;
BEGIN
  SysWrite(1, "A", 1);
  at := -1;
  NEW(v, 3);
  Touch(v^, at);
  SysWrite(1, "B", 1)
END paramnegative.
