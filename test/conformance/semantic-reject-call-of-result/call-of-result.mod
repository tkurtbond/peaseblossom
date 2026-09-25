MODULE callOfResult;
  (* Pick(n)(3, 4) with n a name parses as a guard Pick(n) followed by a
     call; nothing of procedure type can be guarded, so the checker says
     what it really is. A guard with a variable in it, p(n), is still
     "expected a type name". *)
  TYPE
    Op = PROCEDURE (a, b: INTEGER): INTEGER;
    Act = PROCEDURE (k: INTEGER);
    R = RECORD k: INTEGER END;
    P = POINTER TO R;
  VAR x, n: INTEGER; p: P; f: Op; g: PROCEDURE (k: INTEGER): Act;
  PROCEDURE Pick(k: INTEGER): Op;
  BEGIN RETURN NIL
  END Pick;
BEGIN
  x := Pick(n)(3, 4);
  g(n)(2);
  x := ABS(n)(1);
  x := p(n).k;
  f := Pick(n); x := f(3, 4)
END callOfResult.
