MODULE withNotImplemented;
  (* WITH's type-test-and-guard form (Oberon2.pdf §9.11) is deferred to
     PLAN.md Phase 6, alongside type-bound procedure dispatch, which it
     shares machinery with - see SemanticActions.Mod's Phase 5 header
     comment. *)

  VAR i: INTEGER;
BEGIN
  WITH i: INTEGER DO
  END
END withNotImplemented.
