MODULE figures;
  (* PLAN.md Phase 9 step 6: the library half of the cross-module
     type-bound-procedure fixture (see client.mod). Exports records with
     procedures bound to them - pointer receivers and VAR receivers - and
     one procedure that is *not* exported but still holds a ProcTab slot
     the importer must number around. *)
  TYPE
    Figure* = POINTER TO FigureDesc;
    FigureDesc* = RECORD
      id*: INTEGER;
      secret: INTEGER
    END;
    Mark* = RECORD n*: INTEGER END;
  VAR
    current*: Figure;
    tally*: Mark;

  PROCEDURE NewFigure*(id: INTEGER): Figure;
    VAR f: Figure;
  BEGIN
    NEW(f); f.id := id; f.secret := 40;
    RETURN f
  END NewFigure;

  PROCEDURE (f: Figure) Area*(): INTEGER;
  BEGIN RETURN 1 END Area;

  PROCEDURE (f: Figure) Name*(): INTEGER;
  BEGIN RETURN 10 END Name;

  (* library code that dispatches to whatever the importer overrode *)
  PROCEDURE (f: Figure) Describe*(): INTEGER;
  BEGIN RETURN f.Name() * 100 + f.Area() END Describe;

  PROCEDURE (f: Figure) Audit(): INTEGER;
  BEGIN RETURN f.secret END Audit;

  (* reaches the hidden procedure through the ProcTab *)
  PROCEDURE (f: Figure) Secret*(): INTEGER;
  BEGIN RETURN f.Audit() END Secret;

  PROCEDURE (VAR m: Mark) Value*(): INTEGER;
  BEGIN RETURN m.n END Value;

  PROCEDURE (VAR m: Mark) Double*(): INTEGER;
  BEGIN RETURN 2 * m.Value() END Double;

  (* an ordinary procedure taking a VAR record: its callers pass the tag *)
  PROCEDURE Measure*(VAR m: Mark): INTEGER;
  BEGIN RETURN m.Value() + 1 END Measure;

  (* the same, for a record only this module knows the extension of *)
  PROCEDURE ValueOf*(VAR m: Mark): INTEGER;
  BEGIN RETURN m.Double() END ValueOf;

BEGIN
  current := NewFigure(3); tally.n := 21
END figures.
