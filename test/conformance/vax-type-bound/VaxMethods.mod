MODULE VaxMethods;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 6): type-bound procedures across modules, a hidden one
     overridden, calls through the receiver's ProcTab and direct ones, the
     base type's with P^, pointer and VAR receivers - a VAR record
     parameter's tag, a block's, a guarded one's, a record variable's,
     field's and element's own type - a ProcTab a type declared in a
     procedure inherits, WITH, an imported variable's, and an open array
     after the receiver. The debugger runs examine what it computes and
     SquareDesc's ProcTab; mode 1 calls through a NIL pointer (trap 4),
     mode 2 fails a guard on a receiver (trap 5), mode 3 calls a VAR
     receiver's procedure through a NIL pointer (trap 4). *)
  IMPORT L := VaxMethLib;
  TYPE
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (L.CircleDesc) side: INTEGER END;
    Twice = RECORD (L.Counter) adds: INTEGER END;
    Node = POINTER TO NodeDesc;
    NodeDesc = RECORD val: INTEGER; next: Node END;
    Box = RECORD c: L.Counter; cs: ARRAY 3 OF L.Counter END;
    CP = POINTER TO L.Counter;
  VAR
    s: L.Shape; c: L.Circle; q: Square; n, m: Node; cp: CP; k: L.Counter; t: Twice; box: Box;
    arr: ARRAY 4 OF INTEGER; i, mode: INTEGER;
    code1, code2, code3, dispatched, counted, twice, sum, bumped, block, static, guarded, local,
    narrowed, imported, total, all, last: INTEGER;

  PROCEDURE (q: Square) Area*(): INTEGER;
  BEGIN RETURN q.side * q.side + q.Area^()
  END Area;

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

  PROCEDURE Guarded(VAR c: L.Counter): INTEGER;
  BEGIN c(Twice).Add(100); RETURN c(Twice).adds
  END Guarded;

  PROCEDURE Local(): INTEGER;
    TYPE Thrice = RECORD (Twice) z: INTEGER END;
    VAR h: Thrice;
  BEGIN
    h.n := 0; h.adds := 0; Use(h, 4); h.Add(1); RETURN h.Get() * 10 + h.adds
  END Local;

  PROCEDURE Narrow(s: L.Shape): INTEGER;
  BEGIN
    WITH s: Square DO RETURN s.Area() * 100 + s.Area^() ELSE RETURN s.Area() END
  END Narrow;

BEGIN
  NEW(s); s.x := 1; NEW(c); c.x := 2; c.r := 3; NEW(q); q.x := 4; q.r := 5; q.side := 6;
  code1 := s.Code(); code2 := c.Code(); code3 := q.Code();
  s := q; dispatched := s.Area();
  k.n := 0; k.Add(5); Use(k, 1); counted := k.Get();
  t.n := 0; t.adds := 0; t.Add(5); Use(t, 1); twice := t.Get() * 10 + t.adds;
  n := NIL;
  FOR i := 1 TO 4 DO NEW(m); m.val := i; m.next := n; n := m END;
  sum := n.Sum(); n.Bump(10); n.next.Bump(1); bumped := n.Sum();
  NEW(cp); cp.n := 0; cp^.Add(4); cp.Add(5); Use(cp^, 6); block := cp.Get();
  box.c.n := 0; box.c.Add(2);
  FOR i := 0 TO 2 DO box.cs[i].n := i; box.cs[i].Add(10) END;
  static := box.c.Get() + box.cs[0].Get() + box.cs[1].Get() + box.cs[2].Get();
  guarded := Guarded(t) * 1000 + t.n;
  local := Local();
  narrowed := Narrow(q) - Narrow(c);
  imported := L.shared.Code(); L.total.Add(1); total := L.total.Get();
  FOR i := 0 TO 3 DO arr[i] := i * i END;
  k.AddAll(arr, last); all := k.n;
  IF mode = 1 THEN s := NIL; i := s.Area()
  ELSIF mode = 2 THEN i := Guarded(k)
  ELSIF mode = 3 THEN cp := NIL; cp.Add(1)
  END
END VaxMethods.
