MODULE functionNoReturn;
  (* Oberon2.pdf §10: "the body of a function procedure must contain a
     return statement which defines its result" - checked shallowly
     here (no BEGIN at all), not via full return-reachability analysis;
     see SemanticActions.Mod's own Phase 6 header comment for that scope
     boundary. *)

  PROCEDURE Foo(): INTEGER;
  END Foo;

BEGIN
END functionNoReturn.
