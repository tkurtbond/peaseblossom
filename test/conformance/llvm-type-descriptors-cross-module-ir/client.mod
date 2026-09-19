MODULE client;
  (* PLAN.md Phase 9 step 1: a record extending another module's record.
     Its descriptor must name the base's tag and inherited procedure by
     the *base's own* module-qualified symbols (@shapes.ShapeDesc.tag,
     @shapes.ShapeDesc.Draw) even though client only ever sees shapes
     through its .sym file - a different Types.RecordType object than
     shapes' own compilation built (see Types.RecordTypeDesc.name). *)
  IMPORT shapes;
  TYPE
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (shapes.ShapeDesc)
      radius: INTEGER;
      owner: Circle
    END;

  PROCEDURE (c: Circle) Area*(): INTEGER;
  BEGIN
    RETURN c.radius
  END Area;
END client.
