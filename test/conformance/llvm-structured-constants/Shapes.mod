MODULE Shapes;
(* Phase 14: exported structured constants, and a record whose fields have
   initializers, for client.mod *)
TYPE
  Point* = RECORD x*, y*: INTEGER END;
  Named* = RECORD (Point) name*: ARRAY 12 OF CHAR := "anon"; weight*: REAL := 0.1; count*: INTEGER := 99 END;
  Row* = ARRAY 3 OF LONGINT;
  Grid* = ARRAY 2 OF Row;
CONST
  origin* = Point{x := -1, y := -2};
  grid* = Grid{{1, 2, 3}, {40, 50}};
  named* = Named{x := 1, name := "first"};
  short* = Row{7};
END Shapes.
