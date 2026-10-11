MODULE pointerindex;
  (* PLAN.md Phase 9 step 7: an index one past the end of a pointer to an open array. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR at: INTEGER;
BEGIN
  Out.String("A");
  at := 4;
  NEW(v, 4);
  v[at] := 1;
  Out.String("B")
END pointerindex.
