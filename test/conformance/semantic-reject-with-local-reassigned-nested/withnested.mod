MODULE withNested;
  (* A local pointer variable cannot be narrowed by WITH if a procedure nested
     in its own procedure assigns it (CheckWithGuard, MayBeReassignedElsewhere;
     the same rule as for a global, semantic-reject-with-global-reassigned,
     reasoned per declaring procedure: only its nested procedures are scanned).
     Run: Swap assigns s, so the WITH on s is rejected. Fine: its nested
     procedure never mentions s (it assigns r), so the WITH is accepted. Real
     voc agrees on both (err 245 for Run only). What a nested procedure that
     only READS s, or passes it on as a VAR argument, does to the rule is left
     out on purpose: voc rejects any mention, poc looks for bare-name
     assignments only. *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD kind: INTEGER END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc) radius: INTEGER END;

  PROCEDURE Run(s: Shape; other: Shape): INTEGER;
    VAR r: INTEGER;
    PROCEDURE Swap;
    BEGIN s := other
    END Swap;
  BEGIN
    r := 0;
    WITH s: Circle DO r := s.radius END;
    RETURN r
  END Run;

  PROCEDURE Fine(s: Shape): INTEGER;
    VAR r: INTEGER;
    PROCEDURE Tally;
    BEGIN r := 5
    END Tally;
  BEGIN
    r := 0;
    WITH s: Circle DO Tally; r := r + s.radius END;
    RETURN r
  END Fine;

BEGIN
END withNested.
