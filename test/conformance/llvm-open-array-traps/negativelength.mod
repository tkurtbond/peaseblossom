MODULE negativelength;
  (* PLAN.md Phase 9 step 7: NEW with a negative length. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
BEGIN
  Out.String("A");
  n := -1;
  NEW(v, n);
  Out.String("B")
END negativelength.
