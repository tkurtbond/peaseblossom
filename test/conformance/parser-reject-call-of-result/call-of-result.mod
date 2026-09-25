MODULE callOfResult;
  (* A designator takes one parameter list, so a returned procedure cannot
     be called in the same expression; one error each, at the second "(",
     and nothing after it. *)
  IMPORT Out;
  TYPE
    Op = PROCEDURE (a, b: INTEGER): INTEGER;
    Act = PROCEDURE (n: INTEGER);
  VAR x: INTEGER; f: Op;
  PROCEDURE Pick(k: INTEGER): Op;
  BEGIN RETURN NIL
  END Pick;
  PROCEDURE Get(k: INTEGER): Act;
  BEGIN RETURN NIL
  END Get;
BEGIN
  Out.Int(Pick(0)(3, 4), 0);
  x := Pick(0)(3, (4 + 1)) + 1;
  Get(1)(2);
  x := Pick(0)(1, 2)(3);
  f := Pick(0); x := f(3, 4)
END callOfResult.
