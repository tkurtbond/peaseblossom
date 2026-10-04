MODULE ConstBad;
  VAR g: INTEGER;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Dyn = RECORD n: INTEGER := g; k: INTEGER END;
    Vector = ARRAY 3 OF INTEGER;
    P = POINTER TO Point;
    Holder = RECORD p: P END;
  CONST
    origin = Point{x := 0};
    d1 = Dyn{k := 1};
    d2 = Dyn{n := 2};
    bad = Point{x := g};
    v = Vector{1, 2, 3};
    out = v[3];
    h = Holder{p := NIL};
  VAR p: Point; i: INTEGER;
  PROCEDURE Change(VAR pt: Point); END Change;
BEGIN
  origin := p;
  origin.x := 1;
  Change(origin);
  i := v[5]
END ConstBad.
