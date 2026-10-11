MODULE nilelement;
  (* PLAN.md Phase 9 step 7: indexing a NIL pointer to an open array. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
BEGIN
  Out.String("A");
  v := NIL;
  v[0] := 1;
  Out.String("B")
END nilelement.
