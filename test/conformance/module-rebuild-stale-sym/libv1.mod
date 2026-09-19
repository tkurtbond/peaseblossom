MODULE lib;
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      next*: Shape
    END;
END lib.
