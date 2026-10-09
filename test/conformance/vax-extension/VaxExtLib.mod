MODULE VaxExtLib;
  (* PLAN.md Phase 16 step 3 (doc/developer/vax-macro32-backend.md, section
     14, item 11): the base types VaxExtension extends, and IS and a type
     guard on one of them. *)
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD x*, y*: INTEGER END;
    Circle* = POINTER TO CircleDesc;
    CircleDesc* = RECORD (ShapeDesc) r*: INTEGER END;

  PROCEDURE Area*(s: Shape): INTEGER;
  BEGIN
    IF s IS Circle THEN RETURN 3 * s(Circle).r * s(Circle).r ELSE RETURN 0 END
  END Area;
END VaxExtLib.
