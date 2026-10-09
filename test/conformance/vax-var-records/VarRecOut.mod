MODULE VarRecOut;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 5): VAR record parameters and records holding pointers,
     printed with Out, so that the program built by the LLVM backend and
     the one built for the VAX can be compared. *)
  IMPORT Out, L := VaxRecLib;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Box = RECORD lo, hi: Point; name: ARRAY 6 OF CHAR END;
    Holder = RECORD c: CHAR; pairs: ARRAY 2 OF L.Pair; head: L.Node END;
    HP = POINTER TO Holder;
    PP = POINTER TO Point;
  VAR
    p: Point; b: Box; boxes: ARRAY 3 OF Box; pp: PP; h, h2: Holder; hp: HP; k: INTEGER;

  PROCEDURE Move(VAR pt: Point; dx, dy: INTEGER);
  BEGIN pt.x := pt.x + dx; pt.y := pt.y + dy
  END Move;

  PROCEDURE Grow(n: INTEGER; VAR bx: Box; s: ARRAY OF CHAR; VAR again: Point);
  BEGIN
    Move(bx.lo, -n, -n); Move(bx.hi, n, n); COPY(s, bx.name); Move(again, 1, 1)
  END Grow;

  PROCEDURE Twice(VAR pt: Point);
  BEGIN Move(pt, pt.x, pt.y)
  END Twice;

  PROCEDURE Show(VAR pt: Point);
  BEGIN Out.Char("("); Out.Int(pt.x, 0); Out.Char(","); Out.Int(pt.y, 0); Out.Char(")")
  END Show;

  PROCEDURE Fill(VAR hd: Holder; n: INTEGER);
    VAR q: L.Node; i: INTEGER;
  BEGIN
    FOR i := 1 TO n DO NEW(q); q.v := i; q.next := hd.head; hd.head := q END;
    hd.pairs[1].a := hd.head; hd.pairs[1].n := 100
  END Fill;

  PROCEDURE Sum(hd: Holder): INTEGER;
    VAR q: L.Node; s: INTEGER;
  BEGIN
    s := 0; q := hd.head; WHILE q # NIL DO s := s + q.v; q := q.next END;
    hd.head := NIL;
    RETURN s
  END Sum;

  PROCEDURE Local(): INTEGER;
    VAR h3: Holder;
  BEGIN
    Fill(h3, 3); RETURN Sum(h3) + L.Count(h3.pairs[1])
  END Local;

BEGIN
  p.x := 1; p.y := 2; Move(p, 10, 20); Show(p); Out.Ln;
  Twice(p); Show(p); Out.Ln;
  b.lo.x := 5; b.hi.y := 5; Grow(2, b, "box", p); Show(b.lo); Show(b.hi); Out.String(b.name); Show(p); Out.Ln;
  boxes[1] := b; k := 1; Grow(1, boxes[k], "b1", boxes[2].hi); Show(boxes[1].lo); Show(boxes[2].hi); Out.Ln;
  NEW(pp); pp.x := 7; Move(pp^, 1, 1); Twice(pp^); Show(pp^); Out.Ln;
  Fill(h, 4); Out.Int(Sum(h), 0); Out.Int(L.Count(h.pairs[1]), 4); Out.Int(L.Count(h.pairs[0]), 4); Out.Ln;
  h2 := h; Fill(h2, 2); Out.Int(Sum(h), 4); Out.Int(Sum(h2), 4); Out.Ln;
  NEW(hp); hp^ := h2; hp.pairs[0].b := h.head; Out.Int(L.Count(hp.pairs[0]), 0); Out.Int(L.Count(hp^.pairs[1]), 4); Out.Ln;
  Out.Int(Local(), 0); Out.Ln
END VarRecOut.
