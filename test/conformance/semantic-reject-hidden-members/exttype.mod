MODULE exttype;
  (* ...and the exported field of the same base stays fine, so the
     rejections above are about visibility, not about extension. *)
  IMPORT lib;
  TYPE
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (lib.ShapeDesc) radius: INTEGER END;
  VAR c: Circle;
  BEGIN
    c.id := 1
END exttype.
