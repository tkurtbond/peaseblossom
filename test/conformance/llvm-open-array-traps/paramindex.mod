MODULE paramindex;
  (* PLAN.md Phase 9 step 7: an index one past the end of an open-array parameter. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  PROCEDURE Touch(VAR a: ARRAY OF INTEGER);
  BEGIN a[SHORT(LEN(a))] := 1 END Touch;
BEGIN
  Out.String("A");
  NEW(v, 3);
  Touch(v^);
  Out.String("B")
END paramindex.
