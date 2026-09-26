MODULE FieldUse;
  IMPORT Out, FieldLib;
  VAR calls: INTEGER;
  PROCEDURE Count(): INTEGER; BEGIN INC(calls); RETURN calls * 10 END Count;
  CONST k = 5;
  TYPE
    Base = RECORD b: INTEGER := k END;
    (* e and f each call Count, e first; plain has none *)
    Ext = RECORD (Base) e, f: INTEGER := Count(); r: REAL := 2; s: ARRAY 6 OF CHAR := "hi"; plain: INTEGER END;
    Holder = RECORD inner: Ext; arr: ARRAY 2, 2 OF Base; p: POINTER TO Base END;
    P = POINTER TO Ext;
    Q = POINTER TO ARRAY OF ARRAY OF Base;
    D = RECORD (FieldLib.Named) extra: INTEGER := 99 END;
  VAR
    g: Ext;
    n: INTEGER := g.e; (* g is initialized first: it is declared first *)
    h: Holder; p: P; q: Q; d: D; list: FieldLib.List; many: FieldLib.Many; named: FieldLib.Named;

  PROCEDURE Local;
    CONST c = 77;
    TYPE L = RECORD a: INTEGER := c; t: RECORD z: CHAR := "Z" END END;
    VAR l: L; ls: ARRAY 3 OF L;
  BEGIN
    Out.Int(l.a, 0); Out.Char(" "); Out.Char(l.t.z); Out.Char(" "); Out.Int(ls[2].a, 0);
    Out.Char(" "); Out.Char(ls[1].t.z); Out.Ln;
    l.a := 0; ls[2].a := 0
  END Local;

BEGIN
  Out.Int(g.b, 0); Out.Char(" "); Out.Int(g.e, 0); Out.Char(" "); Out.Int(g.f, 0); Out.Char(" ");
  Out.Real(g.r, 0); Out.Char(" "); Out.String(g.s); Out.Char(" "); Out.Int(g.plain, 0); Out.Ln;
  Out.Int(n, 0); Out.Ln;
  Out.Int(h.inner.e, 0); Out.Char(" "); Out.Int(h.arr[1, 1].b, 0); Out.Char(" ");
  IF h.p = NIL THEN Out.String("NIL") END; Out.Ln;
  NEW(h.p); Out.Int(h.p.b, 0); Out.Ln;
  NEW(p); Out.Int(p.b, 0); Out.Char(" "); Out.Int(p.e, 0); Out.Char(" "); Out.Int(p.f, 0); Out.Ln;
  NEW(q, 2, 3); Out.Int(q[1, 2].b, 0); Out.Ln;
  FieldLib.Show(d); Out.Char(" "); Out.String(d.name); Out.Char(" "); Out.Int(d.serial, 0);
  Out.Char(" "); Out.Int(d.extra, 0); Out.Ln;
  FieldLib.Show(named); Out.Char(" "); Out.Int(named.serial, 0); Out.Ln;
  NEW(list); Out.Int(list.value, 0); Out.Char(" "); Out.Int(list.inner.z, 0); Out.Ln;
  Out.Real(many[1].w, 0); Out.Ln;
  Local; Local;
  Out.Int(calls, 0); Out.Ln
END FieldUse.
