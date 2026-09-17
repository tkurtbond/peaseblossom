MODULE client;
  (* Resolves lib/greeter.sym purely through "-import-path lib" (see
     test.sh), not through the current-working-directory lookup Phase 7
     originally relied on exclusively. *)

  IMPORT Greeter := greeter;

  VAR x: INTEGER;

  PROCEDURE Run;
  BEGIN
    x := Greeter.Greet()
  END Run;

END client.
