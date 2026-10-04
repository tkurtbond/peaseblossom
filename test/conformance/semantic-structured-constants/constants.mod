MODULE Const;
  VAR g: INTEGER;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Point3 = RECORD (Point) z: INTEGER := 7 END;
    Line = RECORD from, to: Point; width: INTEGER := 1; name: ARRAY 8 OF CHAR; flags: SET END;
    Vector = ARRAY 3 OF REAL;
    Table = ARRAY 256 OF INTEGER;
    Matrix = ARRAY 2, 2 OF INTEGER;
    Dyn = RECORD n: INTEGER := g END;
  CONST
    origin = Point{x := 0, y := 0};
    unit = Point3{x := 1};
    line = Line{to := unit, name := "diag", flags := {1, 3..5}};
    v = Vector{1, 2.5};
    t = Table{3, 4, 5};
    m = Matrix{{1, 2}, {3, 4}};
    four = m[1, 1];
    seven = unit.z;
    w = line.width;
    c = line.name[1];
    sz = t[2] * 10;
  VAR a: ARRAY sz OF CHAR; i: INTEGER; p: Point;
BEGIN
  CASE i OF four: | seven: | sz: END;
  p := origin;
  i := t[i];
  i := m[1, 0]
END Const.
