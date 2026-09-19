MODULE extfield;
  (* Reaching the base's hidden field *through a local extension* must
     not make it accessible: what matters is which record declared the
     field, not which record the access went through. *)
  IMPORT lib;
  TYPE
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (lib.ShapeDesc) radius: INTEGER END;
  VAR c: Circle;
  BEGIN
    c.inner := NIL
END extfield.
