MODULE MethodsOut;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 6): type-bound procedures, printed with Out, so that the
     program built by the LLVM backend and the one built for the VAX can be
     compared: calls through the ProcTab and direct ones, overriding
     across modules, a hidden procedure overridden, P^, pointer and VAR
     receivers of every kind, a type declared in a procedure, WITH, an
     imported variable's, and an open array after the receiver. *)
  IMPORT L := VaxMethLib, Out;
  TYPE
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (L.CircleDesc) side: INTEGER END;
    Twice = RECORD (L.Counter) adds: INTEGER END;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD val: INTEGER; next: Node END;
    Box = RECORD c: L.Counter; cs: ARRAY 3 OF L.Counter END;
    CP = POINTER TO L.Counter;
  VAR
    s: L.Shape; c: L.Circle; q: Square; t: Twice; k: L.Counter; n, m: Node; cp: CP; box: Box;
    arr: ARRAY 4 OF INTEGER; i, last: INTEGER;

  PROCEDURE (q: Square) Area*(): INTEGER;
  BEGIN RETURN q.side * q.side + q.Area^()
  END Area;

  PROCEDURE (q: Square) Code*(): INTEGER;
  BEGIN Out.String("square side="); Out.Int(q.side, 0); Out.Ln; RETURN q.Code^()
  END Code;

  PROCEDURE (VAR t: Twice) Add*(k: INTEGER);
  BEGIN t.Add^(2 * k); INC(t.adds)
  END Add;

  PROCEDURE (n: Node) Sum(): INTEGER;
  BEGIN
    IF n.next = NIL THEN RETURN n.val ELSE RETURN n.val + n.next.Sum() END
  END Sum;

  PROCEDURE (n: Node) Bump(by: INTEGER);
  BEGIN
    WHILE n # NIL DO INC(n.val, by); n := n.next END
  END Bump;

  PROCEDURE Use(VAR c: L.Counter; k: INTEGER);
  BEGIN c.Add(k); c.Add(k)
  END Use;

  PROCEDURE Show(s: L.Shape);
  BEGIN Out.String("code "); Out.Int(s.Code(), 0); Out.String(" area "); Out.Int(s.Area(), 0); Out.Ln
  END Show;

  PROCEDURE Guarded(VAR c: L.Counter);
  BEGIN
    IF c IS Twice THEN c(Twice).Add(100); Out.Int(c(Twice).adds, 0); Out.Ln END;
    c.Add(1)
  END Guarded;

  PROCEDURE Local;
    TYPE Thrice = RECORD (Twice) z: INTEGER END;
    VAR h: Thrice;
  BEGIN
    h.n := 0; h.adds := 0; h.z := 0; Use(h, 3); h.Add(1);
    Out.Int(h.Get(), 0); Out.Int(h.adds, 2); Out.Ln
  END Local;

  PROCEDURE Narrow(s: L.Shape);
  BEGIN
    WITH s: Square DO Out.String("narrow "); Out.Int(s.Area(), 0); Out.Int(s.Area^(), 4); Out.Ln
    ELSE Show(s)
    END
  END Narrow;

BEGIN
  NEW(s); s.x := 1; Show(s);
  NEW(c); c.x := 2; c.r := 3; Show(c);
  NEW(q); q.x := 4; q.r := 5; q.side := 6; Show(q);
  s := q; Out.Int(s.Area(), 0); Out.Int(s(L.Circle).Area(), 4); Out.Ln;
  k.n := 0; k.Add(5); Use(k, 1); Out.Int(k.Get(), 0); Out.Ln;
  t.n := 0; t.adds := 0; t.Add(5); Use(t, 1); Out.Int(t.Get(), 0); Out.Int(t.adds, 2); Out.Ln;
  n := NIL;
  FOR i := 1 TO 4 DO NEW(m); m.val := i; m.next := n; n := m END;
  n.Bump(10); Out.Int(n.Sum(), 0); n.next.Bump(1); Out.Int(n.Sum(), 3); Out.Ln;
  NEW(cp); cp.n := 0; cp^.Add(4); cp.Add(5); Use(cp^, 6); Out.Int(cp.Get(), 0); Out.Ln;
  box.c.n := 0; box.c.Add(2);
  FOR i := 0 TO 2 DO box.cs[i].n := i; box.cs[i].Add(10) END;
  Out.Int(box.c.Get() + box.cs[0].Get() + box.cs[1].Get() + box.cs[2].Get(), 0); Out.Ln;
  Guarded(k); Guarded(t); Out.Int(k.n, 0); Out.Int(t.n, 4); Out.Ln;
  Local;
  Narrow(q); Narrow(c);
  Show(L.shared); L.total.Add(1); Out.Int(L.total.Get(), 0); Out.Ln;
  FOR i := 0 TO 3 DO arr[i] := i * i END;
  k.AddAll(arr, last); t.AddAll(arr, last);
  Out.Int(k.n, 0); Out.Int(t.n, 4); Out.Int(t.adds, 3); Out.Int(last, 3); Out.Ln
END MethodsOut.
