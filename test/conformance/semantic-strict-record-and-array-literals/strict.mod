MODULE Strict;
  TYPE Point = RECORD x, y: INTEGER END;
    Line = RECORD a, b: Point END;
  VAR p: Point; l: Line;
BEGIN
  p := Point{x := 1};
  l := Line{a := {x := 2}, b := p}
END Strict.
