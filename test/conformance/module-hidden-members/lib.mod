MODULE lib;
  (* PLAN.md Phase 9 step 4a: what a .sym must carry so an importer can
     extend a record it cannot fully see. Exported: Shape/ShapeDesc, Base,
     Same, Make, keep. Hidden but reachable, so it must appear: weight,
     inner, stamp (fields of ShapeDesc); Audit (a procedure of Shape);
     Priv/PrivDesc/Deep (unexported types those reach, transitively, and
     Reset, a procedure of Priv - an unexported type's own procedures
     travel with it). Hidden and unreachable, so it must NOT appear:
     Unrelated and ignore. Same = Base checks an exported alias prints
     "Same* = Base", not the cyclic "Base* = Same" pair an earlier writer
     could produce whenever two exported names shared a type. *)
  IMPORT third;
  TYPE
    Deep = RECORD level: INTEGER; mark: CHAR END;
    Priv = POINTER TO PrivDesc;
    PrivDesc = RECORD
      deep: Deep;
      link: Priv
    END;
    Unrelated = RECORD nothing: BOOLEAN END;
    Shape* = POINTER TO ShapeDesc;
    ShapeDesc* = RECORD
      id*: INTEGER;
      weight: LONGINT;
      inner: Priv;
      stamp: third.Stamp;
      next*: Shape
    END;
    Base* = RECORD tag*: INTEGER END;
    Same* = Base;

  VAR
    keep*: Priv;
    ignore: Unrelated;

  PROCEDURE (s: Shape) Draw*;
  BEGIN
  END Draw;

  PROCEDURE (s: Shape) Audit;
  BEGIN
  END Audit;

  PROCEDURE (s: Shape) Area*(scale: INTEGER): INTEGER;
  BEGIN
    RETURN scale
  END Area;

  PROCEDURE (p: Priv) Reset;
  BEGIN
  END Reset;

  PROCEDURE Make*(): Shape;
    VAR s: Shape;
  BEGIN
    RETURN s
  END Make;
END lib.
