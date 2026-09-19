MODULE client;
  (* Extends lib.ShapeDesc, whose hidden members it can neither name nor
     see. View adds nothing, so its layout must equal ShapeDesc's exactly
     (see module-hidden-members). CircleDesc reuses two
     hidden base names - a field (weight) and a procedure (Audit, with a
     different signature) - which real voc accepts as new, separate
     members rather than clashes or overrides. *)
  IMPORT lib;
  TYPE
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (lib.ShapeDesc)
      radius: INTEGER;
      weight: INTEGER;
      spare: lib.Shape
    END;
    View = RECORD (lib.ShapeDesc) END;

  PROCEDURE (c: Circle) Draw*;
  BEGIN
    c.weight := 1
  END Draw;

  PROCEDURE (c: Circle) Audit(x: INTEGER);
  BEGIN
  END Audit;

  PROCEDURE (c: Circle) Extra*;
  BEGIN
  END Extra;
END client.
