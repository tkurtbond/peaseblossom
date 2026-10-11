MODULE nillength;
  (* PLAN.md Phase 9 step 7: LEN of a NIL pointer to an open array's target. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR n: LONGINT;
BEGIN
  Out.String("A");
  v := NIL;
  n := LEN(v^);
  Out.String("B")
END nillength.
