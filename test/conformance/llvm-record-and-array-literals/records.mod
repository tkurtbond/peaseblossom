MODULE records;
(* Phase 14: record and array literals - assigned, passed as values and to
   open arrays, nested with and without their type's name, made in a loop,
   extensions projected to their base - and structured constants, used whole
   and indexed by constants and by variables *)
IMPORT Out;
TYPE
  Point = RECORD x, y: INTEGER END;
  Point3 = RECORD (Point) z: INTEGER END;
  Line = RECORD from, to: Point; name: ARRAY 8 OF CHAR END;
  Vec = ARRAY 4 OF INTEGER;
  Defaults = RECORD a: INTEGER := 7; b: REAL := 2.5; s: SET := {1, 3}; c: CHAR := "q" END;
  Mat = ARRAY 2, 3 OF INTEGER;
  Node = POINTER TO RECORD key: INTEGER; next: Node END;
  Holder = RECORD p: Point; ns: ARRAY 2 OF Node; flags: SET END;
CONST
  origin = Point{x := 0, y := 0};
  unit = Point3{x := 1, y := 2, z := 3};
  v4 = Vec{10, 20, 30};
  m = Mat{{1, 2, 3}, {4, 5, 6}};
  title = Line{from := Point{x := 1, y := 1}, to := {x := 9, y := 9}, name := "diag"};
  d = Defaults{a := 1};
VAR
  p: Point; q: Point3; l: Line; v: Vec; i, j: INTEGER; dd: Defaults; h: Holder; n: Node;
  r: REAL := 1.25;

PROCEDURE ShowPoint(s: ARRAY OF CHAR; p: Point);
BEGIN Out.String(s); Out.String(" ("); Out.Int(p.x, 0); Out.String(", "); Out.Int(p.y, 0); Out.String(")"); Out.Ln
END ShowPoint;

PROCEDURE Sum(a: ARRAY OF INTEGER): INTEGER;
  VAR k, s: INTEGER;
BEGIN s := 0; FOR k := 0 TO SHORT(LEN(a)) - 1 DO s := s + a[k] END; RETURN s
END Sum;

PROCEDURE Loop(n: INTEGER): INTEGER;
  VAR k, s: INTEGER; t: Point;
BEGIN
  s := 0;
  FOR k := 1 TO n DO t := Point{x := k, y := 2 * k}; s := s + t.x + t.y END;
  RETURN s
END Loop;

PROCEDURE Local;
  VAR a: Vec := Vec{1, 2}; b: Point := Point{y := 5};
BEGIN
  Out.Int(Sum(a), 0); Out.Ln; ShowPoint("local", b)
END Local;

BEGIN
  p := Point{x := 3, y := 4}; ShowPoint("p", p);
  p := Point{x := p.y, y := p.x}; ShowPoint("swapped", p);
  q := Point3{x := 5, z := 7}; Out.Int(q.x, 0); Out.Int(q.y, 3); Out.Int(q.z, 3); Out.Ln;
  p := Point3{x := 8, y := 9, z := 10}; ShowPoint("projected", p);
  ShowPoint("arg", Point{x := 11, y := 12});
  ShowPoint("origin", origin); ShowPoint("unit", unit);
  l := Line{from := {x := 1, y := 2}, to := Point{x := 3, y := 4}, name := "abc"};
  ShowPoint("l.from", l.from); ShowPoint("l.to", l.to); Out.String(l.name); Out.Ln;
  l := title; Out.String(l.name); ShowPoint(" title.to", title.to);
  v := Vec{1, 2, 3, 4}; Out.Int(Sum(v), 0); Out.Ln;
  Out.Int(Sum(Vec{5, 6}), 0); Out.Ln;
  Out.Int(Sum(v4), 0); Out.Ln;
  FOR i := 0 TO 1 DO FOR j := 0 TO 2 DO Out.Int(m[i, j], 2) END END; Out.Ln;
  i := 1; Out.Int(Sum(m[i]), 0); Out.Int(v4[i + 1], 4); Out.Ln;
  Out.Int(Loop(100), 0); Out.Ln;
  dd := Defaults{c := "z"}; Out.Int(dd.a, 0); Out.Char(dd.c); IF 3 IN dd.s THEN Out.String(" 3in") END; Out.Ln;
  dd := d; Out.Int(dd.a, 0); Out.Char(dd.c); Out.Ln;
  NEW(n); n.key := 42;
  h := Holder{p := {x := 1, y := 1}, ns := {n, NIL}, flags := {0 .. 2, 5}};
  Out.Int(h.ns[0].key, 0); IF 5 IN h.flags THEN Out.String(" 5in") END; Out.Ln;
  Local;
  Out.Int(title.from.x + unit.z, 0); Out.Ln
END records.
