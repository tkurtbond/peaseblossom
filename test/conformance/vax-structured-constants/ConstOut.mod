MODULE ConstOut;
  (* prints what VaxConstants' constants give (its comment says why), on
     both backends, and uses them from here, another module *)
  IMPORT SYSTEM, Out, C := VaxConstants;
  VAR a: C.All; v: C.Vector; p: C.Point;

  PROCEDURE Show(x: HUGEINT);
  BEGIN Out.Int(x, 0); Out.Char(" ")
  END Show;

BEGIN
  C.CopyAll(a);
  Out.Char(a.tag); Out.Char(" "); Show(a.s); Show(a.i); Show(a.l); Show(a.h);
  IF a.b THEN Out.String("TRUE ") END;
  IF a.set = {0, 31} THEN Out.String("set ") END;
  IF a.set64 = {1, 63} THEN Out.String("set64 ") END;
  Show(ENTIER(a.r * 100)); Show(ENTIER(a.lr * 100));
  IF a.p = NIL THEN Out.String("NIL ") END;
  Out.String(a.name); Out.Ln;
  Show(C.SumVector()); Show(C.Sum(C.vector)); Show(C.SumOpen(C.vector)); Show(C.vector[4]); Out.Ln;
  Show(C.GridCorners()); Show(C.Corners(C.grid)); Out.Ln;
  v := C.vector; v[5] := 3; Show(C.Sum(v));
  p := C.Point{x := 9, y := -9}; Show(p.x); Show(p.y);
  Show(C.Corners(C.Grid{[1]: {x := 5, y := 5}, {x := 1, y := 1}})); Out.Ln
END ConstOut.
