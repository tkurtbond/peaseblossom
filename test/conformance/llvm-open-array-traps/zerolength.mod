MODULE zerolength;
  (* PLAN.md Phase 9 step 7: NEW with a length of zero (voc traps too). Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
BEGIN
  Out.String("A");
  n := 0;
  NEW(v, n);
  Out.String("B")
END zerolength.
