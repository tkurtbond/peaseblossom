MODULE defaults;
(* Phase 14: literals and field initializers - a literal in an initializer,
   the defaults of the fields and elements a literal leaves out, procedure
   values as elements, and literals in nested procedures that use their
   enclosing procedure's variables *)
IMPORT Out;
TYPE
  Point = RECORD x, y: INTEGER END;
  Box = RECORD corner: Point := Point{x := 10, y := 20}; size: Point := Point{x := 1, y := 1}; id: INTEGER END;
  Boxes = ARRAY 3 OF Box;
  Proc = PROCEDURE (p: Point): INTEGER;
  Ops = RECORD f: Proc; p: Point END;
VAR b: Box; bs: Boxes; o: Ops; s: SHORTINT; li: LONGINT;

PROCEDURE Area(p: Point): INTEGER; BEGIN RETURN p.x * p.y END Area;

PROCEDURE Outer(n: INTEGER);
  VAR base: INTEGER;
  PROCEDURE Inner(): INTEGER;
  BEGIN RETURN Area(Point{x := base, y := n}) END Inner;
  PROCEDURE Show(p: Point); BEGIN Out.Int(p.x, 0); Out.Int(p.y, 3); Out.Ln END Show;
  PROCEDURE Make; BEGIN Show(Point{x := base, y := n}) END Make;
BEGIN base := 100; Make; Out.Int(Inner(), 0); Out.Ln
END Outer;

BEGIN
  Out.Int(b.corner.x, 0); Out.Int(b.size.y, 3); Out.Ln;
  b := Box{id := 3}; Out.Int(b.corner.y, 0); Out.Int(b.id, 3); Out.Ln;
  bs := Boxes{{id := 1}, {corner := {x := 5}, id := 2}};
  Out.Int(bs[1].corner.x, 0); Out.Int(bs[1].corner.y, 3); Out.Int(bs[2].corner.x, 3); Out.Int(bs[2].size.x, 3); Out.Ln;
  o := Ops{f := Area, p := {x := 6, y := 7}}; Out.Int(o.f(o.p), 0); Out.Ln;
  s := 3; li := 100000;
  b := Box{id := s}; Out.Int(b.id, 0); Out.Ln;
  Outer(7)
END defaults.
