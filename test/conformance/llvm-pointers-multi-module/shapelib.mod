MODULE shapelib;
  (* PLAN.md Phase 9 step 5: the library half of the cross-module pointer
     fixture (see client.mod). Exports a pointer type and its record, a
     constructor that calls NEW, and a hidden field the importer's layout
     must still account for. *)
  TYPE
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      hidden: LONGINT;
      next*: Shape
    END;
    Circle* = POINTER TO CircleDesc;
    CircleDesc* = RECORD (ShapeDesc)
      radius*: INTEGER
    END;
  VAR
    created*: INTEGER;
    registry*: Shape;

  PROCEDURE NewShape*(id: INTEGER): Shape;
    VAR s: Shape;
  BEGIN
    NEW(s); s.id := id; s.hidden := 1000 + id;
    s.next := registry; registry := s;
    INC(created);
    RETURN s
  END NewShape;

  PROCEDURE NewCircle*(id, radius: INTEGER): Circle;
    VAR c: Circle;
  BEGIN
    NEW(c); c.id := id; c.hidden := 2000 + id; c.radius := radius;
    c.next := registry; registry := c;
    INC(created);
    RETURN c
  END NewCircle;

  PROCEDURE Hidden*(s: Shape): LONGINT;
  BEGIN
    RETURN s.hidden
  END Hidden;

BEGIN
  created := 0; registry := NIL
END shapelib.
