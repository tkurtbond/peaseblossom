MODULE lib;
  (* PLAN.md Phase 9 step 4a: the members below are in lib.sym (an
     importer's layout depends on them) but must stay unreachable by name
     from any importer - including one that extends the record. *)
  TYPE
    Priv = POINTER TO PrivDesc;
    PrivDesc = RECORD level: INTEGER END;
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      weight: LONGINT;
      inner: Priv
    END;

  PROCEDURE (s: Shape) Audit;
  BEGIN
  END Audit;

  PROCEDURE Make*(): Shape;
    VAR s: Shape;
  BEGIN
    RETURN s
  END Make;
END lib.
