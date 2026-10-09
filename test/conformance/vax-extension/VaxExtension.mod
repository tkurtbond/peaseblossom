MODULE VaxExtension;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): record extension across modules and in a procedure, IS
     and type guards on pointers and on VAR record parameters, WITH with
     and without ELSE, and the check of an assignment to a record whose
     dynamic type may differ from its static type. The debugger runs
     examine what it computes and the descriptors' extension levels and
     base types; mode 1 fails a guard (trap 5), mode 2 a WITH without ELSE
     (trap 6), modes 3, 4 and 5 assign a ShapeDesc to a CircleDesc through
     a pointer, a VAR parameter and a guarded VAR parameter (trap 13), mode
     6 tests NIL (trap 4). *)
  IMPORT L := VaxExtLib;
  TYPE
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (L.ShapeDesc) side: INTEGER END;
    Big = POINTER TO BigDesc;
    BigDesc = RECORD (L.CircleDesc) next: L.Shape END;
  VAR
    s, t: L.Shape; c: L.Circle; q: Square; b: Big;
    tests, area, kinds, r, side, widened, tags, copied, assigned, local, mode: INTEGER;
    sd: L.ShapeDesc; cd: L.CircleDesc;

  PROCEDURE Kind(s: L.Shape): INTEGER;
  BEGIN
    WITH s: Big DO RETURN 4
    | s: L.Circle DO RETURN s.r - s.r + 2
    | s: Square DO RETURN s.side - s.side + 3
    ELSE RETURN 1
    END
  END Kind;

  PROCEDURE Widen(VAR d: L.ShapeDesc): INTEGER;
  BEGIN
    IF d IS L.CircleDesc THEN d(L.CircleDesc).r := d(L.CircleDesc).r + 1; RETURN 1 END;
    RETURN 0
  END Widen;

  PROCEDURE Tag(VAR d: L.ShapeDesc): INTEGER;
  BEGIN
    WITH d: BigDesc DO RETURN 40
    | d: L.CircleDesc DO RETURN d.r + 20
    END
  END Tag;

  PROCEDURE Copy(VAR d: L.ShapeDesc; e: L.ShapeDesc);
  BEGIN
    d := e
  END Copy;

  PROCEDURE Set(VAR d: L.ShapeDesc; VAR e: L.CircleDesc);
  BEGIN
    d(L.CircleDesc) := e
  END Set;

  PROCEDURE Local(): INTEGER;
    TYPE Ring = POINTER TO RECORD (BigDesc) inner: INTEGER END;
    VAR g: Ring; x: L.Shape;
  BEGIN
    NEW(g); g.inner := 3; x := g;
    IF x IS Ring THEN RETURN x(Ring).inner ELSE RETURN 0 END
  END Local;

BEGIN
  NEW(c); c.x := 1; c.y := 2; c.r := 5; s := c;
  NEW(q); q.side := 4; NEW(b); b.r := 7; b.next := q;
  tests := 0;
  IF s IS L.Circle THEN INC(tests) END;
  IF s IS Square THEN INC(tests, 10) END;
  t := b; IF t IS L.Circle THEN INC(tests, 100) END;
  IF t IS Big THEN INC(tests, 1000) END;
  area := L.Area(s);
  NEW(t); kinds := Kind(s) * 1000 + Kind(q) * 100 + Kind(b) * 10 + Kind(t);
  s(L.Circle).r := 6; r := c.r;
  t := b; t(Big).next(Square).side := 9; side := q.side;
  widened := Widen(c^) * 10 + Widen(q^);
  tags := Tag(c^) * 100 + Tag(b^);
  sd := c^; NEW(t); t^ := sd; copied := t.x * 10 + t.y;
  cd.x := 8; cd.y := 0; cd.r := 9; Set(c^, cd); assigned := c.x * 100 + c.y * 10 + c.r;
  local := Local();
  IF mode = 1 THEN s := q; c := s(L.Circle)
  ELSIF mode = 2 THEN local := Tag(t^)
  ELSIF mode = 3 THEN s := c; s^ := sd
  ELSIF mode = 4 THEN Copy(c^, sd)
  ELSIF mode = 5 THEN Set(b^, cd)
  ELSIF mode = 6 THEN s := NIL; IF s IS L.Circle THEN local := 0 END
  END
END VaxExtension.
