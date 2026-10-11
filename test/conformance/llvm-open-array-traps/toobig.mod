MODULE toobig;
  (* PLAN.md Phase 9 step 7: NEW of more than the heap will supply: NIL, not a trap. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
BEGIN
  Out.String("A");
  n := 1000000000;
  NEW(v, n);
  IF v = NIL THEN Out.String("N") END;
  Out.String("B")
END toobig.
