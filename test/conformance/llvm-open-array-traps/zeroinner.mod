MODULE zeroinner;
  (* PLAN.md Phase 9 step 7: NEW with a zero length in the second dimension. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR m: POINTER TO ARRAY OF ARRAY OF INTEGER; n: LONGINT;
BEGIN
  Out.String("A");
  n := 0;
  NEW(m, 3, n);
  Out.String("B")
END zeroinner.
