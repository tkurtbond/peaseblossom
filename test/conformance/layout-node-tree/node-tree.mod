MODULE nodeTree;
  (* PLAN.md Phase 4's "ASSERT computed sizes/offsets... for both a
     32-bit and 64-bit target model" fixture, adapted to this project's
     golden-file convention (poc has no codegen yet to ASSERT through) -
     see Poc.Mod's DumpLayout. Node/CenterNode is the report's own
     record-extension example family; Node's self-reference via
     POINTER TO is exactly what SemanticActions.Mod's early-registration
     fix (see its ResolveType header comment) exists to make legal. *)

  TYPE
    Node = RECORD
      name: ARRAY 5 OF CHAR;
      value: LONGINT;
      left, right: POINTER TO Node
    END;
    CenterNode = RECORD (Node)
      weight: LONGREAL
    END;
    Numbers = ARRAY 4 OF INTEGER;
BEGIN
END nodeTree.
