MODULE boundir;
  (* PLAN.md Phase 9 step 6: the IR for type-bound procedures and the
     hidden tag of a VAR record parameter, at both word sizes: a pointer
     receiver dispatched through a base pointer (indirect call through the
     ProcTab slot) and called on an exactly-known type (direct call), a
     base-type "^" call, a VAR receiver with its tag argument, a VAR record
     parameter relayed, tested (IS), guarded and narrowed (WITH). *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD id: INTEGER END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc) radius: INTEGER END;
    Point = RECORD x: INTEGER END;
    Point3 = RECORD (Point) z: INTEGER END;
  VAR
    s: Shape; c: Circle; pt: Point; p3: Point3; result: INTEGER;

  PROCEDURE (s: Shape) Area(): INTEGER;
  BEGIN RETURN s.id END Area;

  PROCEDURE (s: Circle) Area(): INTEGER;
  BEGIN RETURN s.Area^() + s.radius END Area;

  PROCEDURE (VAR p: Point) Sum(): INTEGER;
  BEGIN RETURN p.x END Sum;

  PROCEDURE (VAR p: Point3) Sum(): INTEGER;
  BEGIN RETURN p.Sum^() + p.z END Sum;

  PROCEDURE Relay(VAR p: Point): INTEGER;
    VAR z: INTEGER;
  BEGIN
    z := 0;
    IF p IS Point3 THEN z := p(Point3).z END;
    WITH p: Point3 DO z := z + p.z END;
    RETURN p.Sum() + z
  END Relay;

BEGIN
  NEW(c); s := c;
  result := s.Area();
  result := c.Area();
  result := pt.Sum() + p3.Sum();
  result := Relay(pt) + Relay(p3)
END boundir.
