MODULE matrixindex;
  (* PLAN.md Phase 9 step 7: an index past the inner dimension of a two-dimensional open array. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR m: POINTER TO ARRAY OF ARRAY OF INTEGER; at: INTEGER;
BEGIN
  Out.String("A");
  at := 5;
  NEW(m, 3, 5);
  m[2, at] := 1;
  Out.String("B")
END matrixindex.
