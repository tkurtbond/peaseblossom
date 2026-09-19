MODULE shapes;
  (* The imported base: an exported record with one pointer field and one
     type-bound procedure. *)
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      next*: Shape
    END;

  PROCEDURE (s: Shape) Draw*;
  BEGIN
  END Draw;
END shapes.
