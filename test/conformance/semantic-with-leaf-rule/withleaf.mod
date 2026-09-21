MODULE withLeaf;
  (* WITH on a pointer variable, voc's "leaf" rule (SemanticActions, the WITH
     section comment; AGENTS.md, Nested procedures): a variable
     mentioned from a procedure other than the one that declares it - read or
     written, as a VAR argument, anywhere - is never narrowed; a module-level
     variable counts as declared outside every procedure. Decided by declared
     identity, not spelling. Each "rejected" below is line-for-line what real
     voc reports (err 245), each "accepted" what it accepts. *)
  TYPE
    Shape = POINTER TO ShapeDesc;
    ShapeDesc = RECORD kind: INTEGER END;
    Circle = POINTER TO CircleDesc;
    CircleDesc = RECORD (ShapeDesc) radius: INTEGER END;

  VAR
    readGlobal, untouchedGlobal, varArgGlobal, inProcGlobal: Shape;
    r: INTEGER;

  PROCEDURE Replace(VAR p: Shape; q: Shape);
  BEGIN p := q
  END Replace;

  PROCEDURE ReadsGlobal;
  BEGIN r := readGlobal.kind
  END ReadsGlobal;

  PROCEDURE PassesGlobal;
  BEGIN Replace(varArgGlobal, NIL)
  END PassesGlobal;

  PROCEDURE GuardsGlobal;
  BEGIN
    WITH inProcGlobal: Circle DO r := inProcGlobal.radius END (* rejected: a WITH in a procedure mentions it there *)
  END GuardsGlobal;

  PROCEDURE VarParam(VAR s: Shape);
  BEGIN
    WITH s: Circle DO r := s.radius END (* rejected: an alias of the caller's variable *)
  END VarParam;

  PROCEDURE NestedReads(s: Shape);
    PROCEDURE Look;
    BEGIN r := s.kind
    END Look;
  BEGIN
    WITH s: Circle DO r := s.radius END (* rejected: Look mentions s *)
  END NestedReads;

  PROCEDURE NestedAssigns(s, other: Shape);
    PROCEDURE Swap;
    BEGIN s := other
    END Swap;
  BEGIN
    WITH s: Circle DO r := s.radius END (* rejected *)
  END NestedAssigns;

  PROCEDURE NestedVarArg(s, other: Shape);
    PROCEDURE Hit;
    BEGIN Replace(s, other)
    END Hit;
  BEGIN
    WITH s: Circle DO Hit; r := s.radius END (* rejected: Hit can reassign s through Replace *)
  END NestedVarArg;

  PROCEDURE NestedGuards(s: Shape);
    PROCEDURE Inner;
    BEGIN
      WITH s: Circle DO r := s.radius END (* rejected: this WITH mentions s from Inner *)
    END Inner;
  BEGIN
    r := 0
  END NestedGuards;

  PROCEDURE NestedSilent(s: Shape);
    PROCEDURE Tally;
    BEGIN r := r + 1
    END Tally;
  BEGIN
    WITH s: Circle DO Tally; r := r + s.radius END (* accepted: Tally never mentions s *)
  END NestedSilent;

  PROCEDURE NestedShadows(s: Shape);
    PROCEDURE Other;
      VAR s: INTEGER;
    BEGIN s := 3
    END Other;
  BEGIN
    WITH s: Circle DO Other; r := s.radius END (* accepted: Other's s is its own *)
  END NestedShadows;

  PROCEDURE NestedOwnParameter(s: Shape);
    PROCEDURE Inner(p: Shape);
    BEGIN
      WITH p: Circle DO r := p.radius END (* accepted: p is Inner's own *)
    END Inner;
  BEGIN
    Inner(s)
  END NestedOwnParameter;

  PROCEDURE OwnBodyAssigns(s: Shape; other: Circle);
  BEGIN
    WITH s: Circle DO s := other; r := 0 END (* accepted: only the declaring procedure itself *)
  END OwnBodyAssigns;

BEGIN
  WITH readGlobal: Circle DO r := readGlobal.radius END; (* rejected: ReadsGlobal mentions it *)
  WITH untouchedGlobal: Circle DO r := untouchedGlobal.radius END; (* accepted: no procedure does *)
  WITH varArgGlobal: Circle DO r := varArgGlobal.radius END (* rejected: PassesGlobal mentions it *)
END withLeaf.
