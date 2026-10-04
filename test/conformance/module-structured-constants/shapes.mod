MODULE shapes;
  TYPE
    Point* = RECORD x*, y*: INTEGER END;
    Point3* = RECORD (Point) z*: INTEGER := 7 END;
    Secret* = RECORD a*: INTEGER; hidden: INTEGER := 3 END;
    Line* = RECORD from*, to*: Point; width*: INTEGER := 1; name*: ARRAY 8 OF CHAR; flags*: SET; r*: REAL END;
    Table* = ARRAY 256 OF INTEGER;
    Matrix* = ARRAY 2, 2 OF INTEGER;
    Private = RECORD p*: INTEGER END;
    Init* = RECORD origin*: Point := Point{x := 5}; n*: CHAR := "q" END;
  CONST
    one* = 1;
    origin* = Point{x := 0, y := 0};
    unit* = Point3{x := 1, y := 2};
    line* = Line{to := unit, name := "diag", flags := {1, 3..5}, r := 2.5};
    t* = Table{3, 4, 5};
    m* = Matrix{{1, 2}, {3, 4}};
    s* = Secret{a := 9, hidden := 4};
    pr* = Private{p := 11};
END shapes.
