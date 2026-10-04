MODULE Lits;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Point3 = RECORD (Point) z: INTEGER := 7 END;
    Line = RECORD from, to: Point; width: INTEGER := 1; name: ARRAY 8 OF CHAR; flags: SET END;
    Vector = ARRAY 3 OF REAL;
    Matrix = ARRAY 2, 2 OF REAL;
    Grid = ARRAY 2 OF RECORD a, b: CHAR END;
    P = POINTER TO Point;
  VAR p: Point; q: Point3; l: Line; v: Vector; m: Matrix; g: Grid; s: SET; i: INTEGER;
  PROCEDURE Sum(a: ARRAY OF REAL): REAL;
  BEGIN RETURN a[0]
  END Sum;
  PROCEDURE Show(pt: Point);
  END Show;
BEGIN
  p := Point{x := 1, y := 2};
  p := Point{};
  q := Point3{x := i, z := 3};
  p := Point3{y := 5};
  l := Line{from := p, to := Point{x := 3}, name := "abc", flags := {1, 3..5}};
  l := Line{from := {x := 1, y := 2}, flags := {1} + s};
  v := Vector{1, 2.5};
  m := Matrix{{1, 0}, {0, 1}};
  g := Grid{{a := "x"}, {b := "y"}};
  Show(Point{x := 9});
  i := SHORT(ENTIER(Sum(Vector{1, 2, 3})))
END Lits.
