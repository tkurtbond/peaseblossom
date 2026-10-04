MODULE Shapes;
  (* Record and array literals, and a structured constant: poc's extensions *)
  IMPORT Out;
  TYPE
    Point = RECORD x, y: INTEGER END;
    Line = RECORD from, to: Point; width: INTEGER := 1 END;
    Path = ARRAY 4 OF Point;
  CONST
    origin = Point{x := 0, y := 0};
  VAR line: Line; path: Path; i: INTEGER;
BEGIN
  line := Line{from := origin, to := Point{x := 3, y := 4}};
  Out.Int(line.to.x, 0); Out.Int(line.to.y, 2); Out.Int(line.width, 2); Out.Ln;
  path := Path{{x := 1, y := 1}, {x := 2, y := 4}, {x := 3, y := 9}};
  FOR i := 0 TO LEN(path) - 1 DO Out.Int(path[i].y, 2) END; Out.Ln
END Shapes.
