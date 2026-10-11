MODULE paramnegative;
  (* PLAN.md Phase 9 step 7: a negative index into an open-array parameter. Prints "A", then
     must trap before it can print "B" (see test.sh). *)
  IMPORT Out;
  TYPE Vector = POINTER TO ARRAY OF INTEGER;
  VAR v: Vector;
  VAR at: INTEGER;
  PROCEDURE Touch(VAR a: ARRAY OF INTEGER; i: INTEGER);
  BEGIN a[i] := 1 END Touch;
BEGIN
  Out.String("A");
  at := -1;
  NEW(v, 3);
  Touch(v^, at);
  Out.String("B")
END paramnegative.
