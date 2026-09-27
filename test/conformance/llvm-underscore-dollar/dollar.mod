MODULE dollar_main;
IMPORT Out, Ss$Def;

TYPE
  $anon1 = RECORD n: INTEGER := 5 END;  (* named like the backend's anonymous records *)
  $rec1 = RECORD d: Ss$Def.DSC$DESCRIPTOR END;
  _pair = RECORD a: RECORD x: INTEGER := 3 END; b: $anon1 END;

VAR
  d: Ss$Def.DSC$DESCRIPTOR; r: $rec1; p: _pair; a: $anon1;
  _count, $total: INTEGER;
  q: POINTER TO RECORD k: INTEGER END;  (* an anonymous record: the backend names it *)

PROCEDURE _add($x, _y: INTEGER): INTEGER;
BEGIN
  RETURN $x + _y
END _add;

BEGIN
  d.DSC$W_LENGTH := 10;
  _count := Ss$Def.SS$_NORMAL; $total := _add(_count, Ss$Def.$first);
  Out.Int($total, 0); Out.Ln;
  IF Ss$Def.LIB$SUCCESS(Ss$Def.SS$_NORMAL) & ~Ss$Def.LIB$SUCCESS(Ss$Def.SS$_ACCVIO) THEN Out.String("success test ok") END; Out.Ln;
  Out.Int(d.DSC$W_LENGTH, 0); Out.Char(" "); Out.Int(d.$init, 0); Out.Char(" "); Out.Int(r.d.$init, 0); Out.Ln;
  NEW(q); q.k := 42; Out.Int(q.k, 0); Out.Ln;
  Out.Int(a.n, 0); Out.Char(" "); Out.Int(p.a.x, 0); Out.Char(" "); Out.Int(p.b.n, 0); Out.Ln
END dollar_main.
