MODULE lib;
  (* libv1 plus one hidden 8-byte field - the only change, so any importer's
     layout of ShapeDesc must grow with it. *)
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      weight: HUGEINT;
      next*: Shape
    END;
END lib.
