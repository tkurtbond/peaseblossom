MODULE FieldsOut;
  (* prints the defaults VaxFieldsUse's records get (its comment says
     why), on both backends *)
  IMPORT Out, F := VaxFields, U := VaxFieldsUse;
  VAR k, m, before, v, w: INTEGER; p: F.Point;

  PROCEDURE ShowPoint(p: F.Point);
  BEGIN Out.Int(p.x, 0); Out.Int(p.y, 2); Out.Char(" "); Out.Char(p.tag); Out.Char(" ")
  END ShowPoint;

  PROCEDURE ShowNamed(n: F.Named);
  BEGIN ShowPoint(n); Out.String(n.name); Out.Int(n.serial, 2); Out.Int(n.other, 3); Out.Char(" ")
  END ShowNamed;

  PROCEDURE ShowLocal;
  BEGIN
    U.Local(before, p, v, w);
    Out.Int(before, 0); Out.Char(" "); ShowPoint(p); Out.Int(v, 0); Out.Int(w, 4); Out.Ln
  END ShowLocal;

BEGIN
  ShowNamed(U.n); ShowNamed(U.copy); Out.Int(U.seen, 0); Out.Ln;
  Out.Int(U.h.count, 0); Out.Char(" "); ShowPoint(U.h.corner); ShowPoint(U.h.row[0]); ShowPoint(U.h.row[2]); Out.Ln;
  ShowNamed(U.lab); Out.Char(U.lab.label); Out.Int(U.lab.size, 3); Out.Ln;
  IF U.anonymous.flag THEN Out.Int(U.anonymous.code, 0) END; Out.Ln;
  U.Make;
  Out.Int(U.list.value, 0); Out.Int(U.list.next.value, 2); Out.Ln;
  ShowPoint(U.points[0]); ShowPoint(U.points[3]); Out.Ln;
  FOR k := 0 TO 1 DO FOR m := 0 TO 2 DO Out.Int(U.open[k, m].serial, 3) END END; Out.Ln;
  ShowNamed(U.open[1, 2]); Out.Ln;
  ShowLocal; ShowLocal;
  U.Copy; ShowNamed(U.copy); Out.Ln (* a copy gets no defaults *)
END FieldsOut.
