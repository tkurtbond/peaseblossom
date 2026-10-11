MODULE overflow;
  (* PLAN.md Phase 9 step 7: NEW whose size does not fit in 64 bits. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR m: POINTER TO ARRAY OF ARRAY OF INTEGER; n: HUGEINT;
BEGIN
  Out.String("A");
  n := 5000000000;
  NEW(m, n, n);
  Out.String("B")
END overflow.
