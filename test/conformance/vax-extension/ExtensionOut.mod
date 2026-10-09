MODULE ExtensionOut;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): record extension, printed with Out, so that the program
     built by the LLVM backend and the one built for the VAX can be
     compared: IS, type guards and WITH on pointers and VAR record
     parameters, inherited fields, assignment of an extension to its base
     type, and an extension declared in a procedure. *)
  IMPORT L := VaxExtLib, Out;
  TYPE
    Square = POINTER TO SquareDesc;
    SquareDesc = RECORD (L.ShapeDesc) side: INTEGER END;
    Big = POINTER TO BigDesc;
    BigDesc = RECORD (L.CircleDesc) next: L.Shape END;
  VAR
    s, t: L.Shape; c: L.Circle; q: Square; b: Big; n: INTEGER;
    sd: L.ShapeDesc; cd: L.CircleDesc;

  PROCEDURE Flag(f: BOOLEAN);
  BEGIN
    IF f THEN Out.String(" 1") ELSE Out.String(" 0") END
  END Flag;

  PROCEDURE Kind(s: L.Shape): INTEGER;
  BEGIN
    WITH s: Big DO RETURN 4
    | s: L.Circle DO RETURN s.r - s.r + 2
    | s: Square DO RETURN s.side - s.side + 3
    ELSE RETURN 1
    END
  END Kind;

  PROCEDURE Name(VAR d: L.ShapeDesc);
  BEGIN
    WITH d: BigDesc DO Out.String("big"); Out.Int(d.r, 2)
    | d: L.CircleDesc DO Out.String("circle"); Out.Int(d.r, 2)
    | d: SquareDesc DO Out.String("square"); Out.Int(d.side, 2)
    ELSE Out.String("shape")
    END;
    IF d IS L.CircleDesc THEN Out.String(" round") END;
    Out.Ln
  END Name;

  PROCEDURE Set(VAR d: L.ShapeDesc; VAR e: L.CircleDesc);
  BEGIN
    d(L.CircleDesc) := e
  END Set;

  PROCEDURE Local(): INTEGER;
    TYPE Ring = POINTER TO RECORD (BigDesc) inner: INTEGER END;
    VAR g: Ring; x: L.Shape;
  BEGIN
    NEW(g); g.inner := 3; g.r := 2; x := g;
    WITH x: Ring DO RETURN x.inner * 10 + x.r ELSE RETURN 0 END
  END Local;

BEGIN
  NEW(c); c.x := 1; c.y := 2; c.r := 5; s := c;
  NEW(q); q.x := 3; q.side := 4; NEW(b); b.r := 7; b.next := q; NEW(t);
  Out.String("tests");
  Flag(s IS L.Circle); Flag(s IS Square);
  s := b; Flag(s IS L.Circle); Flag(s IS Big);
  s := q; Flag(s IS L.Circle); Flag(t IS L.Circle); Out.Ln;
  Out.String("area"); Out.Int(L.Area(c), 3); Out.Int(L.Area(q), 2); Out.Int(L.Area(b), 4); Out.Ln;
  Out.String("kinds"); Out.Int(Kind(c), 2); Out.Int(Kind(q), 2); Out.Int(Kind(b), 2); Out.Int(Kind(t), 2); Out.Ln;
  Name(c^); Name(q^); Name(b^); Name(t^);
  s := c; s(L.Circle).r := 6; Out.String("r"); Out.Int(c.r, 2); Out.Ln;
  s := b; s(Big).next(Square).side := 9; Out.String("side"); Out.Int(q.side, 2); Out.Int(q.x, 2); Out.Ln;
  sd := c^; Out.String("sd"); Out.Int(sd.x, 2); Out.Int(sd.y, 2); Out.Ln;
  t^ := sd; Out.String("t"); Out.Int(t.x, 2); Out.Int(t.y, 2); Out.Ln;
  cd.x := 8; cd.y := 0; cd.r := 9; Set(c^, cd);
  Out.String("set"); Out.Int(c.x, 2); Out.Int(c.y, 2); Out.Int(c.r, 2); Out.Ln;
  n := Local(); Out.String("local"); Out.Int(n, 3); Out.Ln
END ExtensionOut.
